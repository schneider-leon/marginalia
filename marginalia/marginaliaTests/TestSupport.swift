//
//  TestSupport.swift
//  marginaliaTests
//
//  Shared helpers. The tests create their own sample files so nothing
//  depends on the environment.
//

import AppKit
import CoreText
import PDFKit
import XCTest
@testable import marginalia

@MainActor
enum TestSupport {

    /// Fresh folder that can be deleted again after the test.
    static func makeTemporaryDirectory(_ label: String = "test") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "marginalia-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// PDF with a real text layer — needed so text selection and
    /// highlighting have anything to grab at all.
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
                string: "Test page \(page)\n\n",
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

    /// Counts pixels that are not (almost) white.
    ///
    /// Deliberately not "dark" pixels: a yellow highlight is light and would
    /// otherwise slip through. Any deviation from white paper is counted, by
    /// brightness *and* saturation.
    ///
    /// The document is deliberately passed in as a parameter: a `PDFPage`
    /// without a living `PDFDocument` renders blank, and more than one test
    /// has already fallen for exactly that.
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

    /// Outside a run loop the UndoManager never closes its automatic
    /// groups — so tests group by hand.
    static func undoGroup(_ manager: UndoManager, _ body: () -> Void) {
        manager.beginUndoGrouping()
        body()
        manager.endUndoGrouping()
    }
}

/// Base for tests that need their own working folder.
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
