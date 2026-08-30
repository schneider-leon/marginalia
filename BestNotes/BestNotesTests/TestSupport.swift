//
//  TestSupport.swift
//  BestNotesTests
//
//  Gemeinsame Helfer. Die Tests legen sich ihre Beispieldateien selbst an,
//  damit nichts von der Umgebung abhaengt.
//

import AppKit
import CoreText
import PDFKit
import XCTest
@testable import BestNotes

@MainActor
enum TestSupport {

    /// Frischer Ordner, der sich nach dem Test wieder loeschen laesst.
    static func makeTemporaryDirectory(_ label: String = "test") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "BestNotes-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// PDF mit echter Textebene — noetig, damit Textauswahl und Markieren
    /// ueberhaupt etwas zu greifen haben.
    @discardableResult
    static func makeSamplePDF(pages: Int = 3, at url: URL) throws -> URL {
        var mediaBox = CGRect(origin: .zero, size: PDFPageFactory.a4)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let body = String(
            repeating: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr. ",
            count: 30
        )
        for page in 1...pages {
            context.beginPDFPage(nil)
            let text = NSMutableAttributedString(
                string: "Testseite \(page)\n\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black]
            )
            text.append(NSAttributedString(
                string: body,
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
            ))
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRangeMake(0, 0),
                CGPath(rect: CGRect(x: 60, y: 60, width: 475, height: 722), transform: nil), nil
            )
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    static func makeImagePNG(size: CGSize = CGSize(width: 400, height: 300), color: NSColor = .blue) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
    }

    /// Zaehlt Pixel, die nicht (nahezu) weiss sind.
    ///
    /// Bewusst nicht „dunkle“ Pixel: ein gelbes Highlight ist hell und waere
    /// sonst durchgerutscht. Gezaehlt wird jede Abweichung von weissem Papier,
    /// nach Helligkeit *und* Saettigung.
    ///
    /// Das Dokument wird bewusst als Parameter durchgereicht: eine `PDFPage`
    /// ohne lebendes `PDFDocument` rendert leer, und genau darauf ist schon
    /// mehr als ein Test hereingefallen.
    static func inkPixelCount(in document: PDFDocument, page index: Int = 0) -> Int {
        guard let page = document.page(at: index) else { return -1 }
        let image = page.thumbnail(of: PDFPageFactory.a4, for: .cropBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return -1 }
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let isPaper = color.brightnessComponent > 0.97 && color.saturationComponent < 0.05
                if !isPaper { count += 1 }
            }
        }
        return count
    }

    /// Ausserhalb eines Runloops schliesst der UndoManager seine automatischen
    /// Gruppen nie — im Test wird deshalb von Hand gruppiert.
    static func undoGroup(_ manager: UndoManager, _ body: () -> Void) {
        manager.beginUndoGrouping()
        body()
        manager.endUndoGrouping()
    }
}

/// Basis fuer Tests, die einen eigenen Arbeitsordner brauchen.
@MainActor
class TemporaryDirectoryTestCase: XCTestCase {
    var workingDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        workingDirectory = try TestSupport.makeTemporaryDirectory(String(describing: Self.self))
    }

    override func tearDown() async throws {
        if let workingDirectory {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
        workingDirectory = nil
        try await super.tearDown()
    }
}
