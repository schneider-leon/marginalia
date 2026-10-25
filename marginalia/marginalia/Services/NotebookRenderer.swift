//
//  NotebookRenderer.swift
//  marginalia
//
//  Burns the typed text (and the guide lines) into the PDF pages.
//
//  The export deliberately creates a *new* document: the working copy in
//  the package stays editable, and the user gets a flat PDF that looks the
//  same everywhere. The text is drawn as real text, not as an image —
//  searching and copying keep working in the result.
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

            // 1. The page itself, including its PDF annotations.
            context.saveGState()
            page.draw(with: .cropBox, to: context)
            context.restoreGState()

            // 2. Images — in PDF coordinates, so without conversion.
            if let pageID = package.pageID(at: index) {
                for overlay in package.overlays.sortedOverlays(for: pageID) {
                    guard case .image(let content) = overlay.content,
                          let data = package.assetData(named: content.assetName),
                          let image = NSImage(data: data),
                          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { continue }
                    context.saveGState()
                    context.setAlpha(content.opacity)
                    context.draw(cgImage, in: overlay.frame)
                    context.restoreGState()
                }
            }

            // 3. Everything else in a top-left coordinate system, because
            //    that is how NSLayoutManager draws. PDF counts from the
            //    bottom left.
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            let textOrigin = CGPoint(x: insets.leading, y: insets.top)
            let textArea = CGRect(origin: textOrigin, size: insets.textAreaSize(for: box.size))

            // Without a view there is no appearance that dynamic colors could
            // resolve against — so we specify one. Otherwise dark mode would
            // draw white on white.
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

    /// A single page with burned-in text and guide lines.
    ///
    /// Returns the page *and* the creating document: PDFKit cannot draw a
    /// page without a document, and the caller has to keep it alive until
    /// the page is inserted.
    static func textPage(
        size: CGSize,
        containerIndex: Int,
        engine: NotebookTextEngine,
        insets: TextInsets,
        ruling: PageRuling
    ) -> (page: PDFPage, owner: PDFDocument)? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)

        context.saveGState()
        context.translateBy(x: 0, y: box.height)
        context.scaleBy(x: 1, y: -1)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let origin = CGPoint(x: insets.leading, y: insets.top)
        let area = CGRect(origin: origin, size: insets.textAreaSize(for: box.size))
        let paper = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        paper.performAsCurrentDrawingAppearance {
            drawRuling(ruling, in: area, lineHeight: lineHeight(of: engine))
            if let range = engine.glyphRange(forContainerAt: containerIndex), range.length > 0 {
                engine.layoutManager.drawBackground(forGlyphRange: range, at: origin)
                engine.layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
            }
        }

        NSGraphicsContext.current = previous
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: data as Data), let page = document.page(at: 0) else {
            return nil
        }
        return (page, document)
    }

    // MARK: - Guide Lines

    private static func lineHeight(of engine: NotebookTextEngine) -> CGFloat {
        let font = (engine.textStorage.length > 0
            ? engine.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil) ?? NotebookTextEngine.defaultFont
        return engine.layoutManager.defaultLineHeight(for: font)
    }

    static func drawRuling(_ ruling: PageRuling, in area: CGRect, lineHeight: CGFloat) {
        guard ruling != .none, lineHeight > 1 else { return }

        // A fixed color for the same reason as with the text: `separatorColor`
        // resolves to white in dark mode.
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
