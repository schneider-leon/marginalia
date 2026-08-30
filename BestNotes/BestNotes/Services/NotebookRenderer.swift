//
//  NotebookRenderer.swift
//  BestNotes
//
//  Brennt den getippten Text (und die Hilfslinien) in die PDF-Seiten ein.
//
//  Der Export erzeugt bewusst ein *neues* Dokument: die Arbeitskopie im Paket
//  bleibt editierbar, der Nutzer bekommt eine flache PDF, die ueberall gleich
//  aussieht. Der Text wird dabei als echter Text gezeichnet, nicht als Bild —
//  Suchen und Kopieren funktionieren im Ergebnis weiter.
//

import AppKit
import CoreGraphics
import Foundation
import PDFKit

@MainActor
enum NotebookRenderer {

    static func flattened(_ package: NotebookPackage) throws -> PDFDocument {
        let engine = NotebookTextEngine(rtf: package.bodyRTF)
        engine.updateContainers(sizes: package.textAreaSizes())
        return try flattened(package, engine: engine)
    }

    static func flattened(_ package: NotebookPackage, engine: NotebookTextEngine) throws -> PDFDocument {
        let source = package.pdf
        let insets = package.info.textInsets
        let ruling = package.info.ruling
        let writableIndices = package.writablePageIndices

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw NotebookPackageError.pdfSerializationFailed
        }
        var defaultBox = CGRect(origin: .zero, size: PDFPageFactory.a4)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw NotebookPackageError.pdfSerializationFailed
        }

        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { continue }
            var box = page.bounds(for: .cropBox)

            context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(
                bytes: &box, length: MemoryLayout<CGRect>.size
            )] as CFDictionary)

            // 1. Die Seite selbst, samt ihrer PDF-Annotationen.
            context.saveGState()
            page.draw(with: .cropBox, to: context)
            context.restoreGState()

            // 2. Alles Weitere in einem oben-links-Koordinatensystem, weil
            //    NSLayoutManager so zeichnet. PDF rechnet von unten links.
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            let textOrigin = CGPoint(x: insets.leading, y: insets.top)
            let textArea = CGRect(origin: textOrigin, size: insets.textAreaSize(for: box.size))

            // Ohne View gibt es keine Darstellung, gegen die dynamische Farben
            // aufloesen koennten — also eine vorgeben. Sonst wird im
            // Dunkelmodus weiss auf weiss gezeichnet.
            let paper = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
            paper.performAsCurrentDrawingAppearance {
                if let containerIndex = writableIndices.firstIndex(of: index) {
                    drawRuling(ruling, in: textArea, lineHeight: lineHeight(of: engine))
                    if let range = engine.glyphRange(forContainerAt: containerIndex), range.length > 0 {
                        engine.layoutManager.drawBackground(forGlyphRange: range, at: textOrigin)
                        engine.layoutManager.drawGlyphs(forGlyphRange: range, at: textOrigin)
                    }
                }
            }

            NSGraphicsContext.current = previous
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()

        guard let document = PDFDocument(data: data as Data) else {
            throw NotebookPackageError.pdfSerializationFailed
        }
        return document
    }

    // MARK: - Hilfslinien

    private static func lineHeight(of engine: NotebookTextEngine) -> CGFloat {
        let font = (engine.textStorage.length > 0
            ? engine.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil) ?? NotebookTextEngine.defaultFont
        return engine.layoutManager.defaultLineHeight(for: font)
    }

    static func drawRuling(_ ruling: PageRuling, in area: CGRect, lineHeight: CGFloat) {
        guard ruling != .none, lineHeight > 1 else { return }

        // Feste Farbe aus demselben Grund wie bei der Schrift: `separatorColor`
        // loest sich im Dunkelmodus zu Weiss auf.
        NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.74, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5

        var y = area.minY + lineHeight
        while y <= area.maxY {
            path.move(to: CGPoint(x: area.minX, y: y))
            path.line(to: CGPoint(x: area.maxX, y: y))
            y += lineHeight
        }

        if ruling == .grid {
            var x = area.minX + lineHeight
            while x <= area.maxX {
                path.move(to: CGPoint(x: x, y: area.minY))
                path.line(to: CGPoint(x: x, y: area.maxY))
                x += lineHeight
            }
        }

        path.stroke()
    }
}
