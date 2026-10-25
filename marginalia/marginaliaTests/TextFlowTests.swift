//
//  TextFlowTests.swift
//  marginaliaTests
//

import AppKit
import PDFKit
import XCTest
@testable import marginalia

@MainActor
final class TextFlowTests: TemporaryDirectoryTestCase {

    private func filledEngine(_ package: NotebookPackage, repeating count: Int) -> NotebookTextEngine {
        let engine = NotebookTextEngine()
        engine.updateContainers(sizes: package.textAreaSizes())
        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "A paragraph with enough text to fill the page. ", count: count),
            attributes: NotebookTextEngine.defaultAttributes
        ))
        return engine
    }

    func testWritingAreaIsPageMinusMargin() throws {
        let package = try NotebookPackage.create(title: "Margin", at: workingDirectory)
        XCTAssertEqual(package.writablePageIndices, [0])
        XCTAssertEqual(
            package.textAreaSizes().first,
            CGSize(width: 595 - 112, height: 842 - 112)
        )
    }

    func testTextOverflowsAndNeedsMorePages() throws {
        let package = try NotebookPackage.create(title: "Flow", at: workingDirectory)
        let area = try XCTUnwrap(package.textAreaSizes().first)

        let engine = filledEngine(package, repeating: 3)
        XCTAssertFalse(engine.overflows)
        XCTAssertEqual(engine.requiredPageCount(pageSize: area), 1)

        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "A paragraph with enough text to fill the page. ", count: 300),
            attributes: NotebookTextEngine.defaultAttributes
        ))
        XCTAssertTrue(engine.overflows)
        let needed = engine.requiredPageCount(pageSize: area)
        XCTAssertGreaterThan(needed, 1)

        while package.writablePageIndices.count < needed {
            try package.insertBlankPage()
        }
        engine.updateContainers(sizes: package.textAreaSizes())
        XCTAssertEqual(engine.containers.count, needed)
        XCTAssertFalse(engine.overflows)
    }

    func testPagesContinueEachOther() throws {
        let package = try NotebookPackage.create(title: "Continuation", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let first = try XCTUnwrap(engine.glyphRange(forContainerAt: 0))
        let second = try XCTUnwrap(engine.glyphRange(forContainerAt: 1))
        XCTAssertGreaterThan(first.length, 0)
        XCTAssertGreaterThan(second.length, 0)
        XCTAssertEqual(second.location, NSMaxRange(first), "Page 2 must start right after page 1")
    }

    func testInsertingAtTheStartPushesTheRestBack() throws {
        let package = try NotebookPackage.create(title: "Push", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let before = try XCTUnwrap(engine.glyphRange(forContainerAt: 0)).length
        engine.textStorage.insert(NSAttributedString(
            string: String(repeating: "New at the start. ", count: 40),
            attributes: NotebookTextEngine.defaultAttributes
        ), at: 0)
        let after = try XCTUnwrap(engine.glyphRange(forContainerAt: 0)).length

        XCTAssertNotEqual(before, after)
        XCTAssertTrue(engine.overflows, "The text must run past the last page")
    }

    /// Without a selection the toggle must affect the *next* typed text —
    /// otherwise bold could only be applied afterwards.
    func testBoldAndItalicWithoutSelectionAffectFurtherTyping() throws {
        let package = try NotebookPackage.create(title: "Format", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Format")
        let engine = session.textEngine

        let field = NSTextView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400),
            textContainer: engine.containers[0]
        )
        field.typingAttributes = NotebookTextEngine.defaultAttributes
        session.activeTextView = field
        XCTAssertEqual(session.selectedTextRange.length, 0)

        session.toggleBold()
        var font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))

        session.toggleItalic()
        font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Bold must not get lost along the way")

        // The state must also be readable, otherwise the toolbar cannot
        // show it.
        XCTAssertTrue(session.isBoldActive)
        XCTAssertTrue(session.isItalicActive)

        session.setFontSize(24)
        font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.pointSize, 24)
        XCTAssertEqual(session.currentFontSize, 24)

        session.toggleBold()
        font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Toggling again takes it back")
        XCTAssertFalse(session.isBoldActive)
        XCTAssertTrue(session.isItalicActive, "Italic stays unaffected")

        // Underline is an attribute of its own, not a font trait
        XCTAssertFalse(session.isUnderlineActive)
        session.toggleUnderline()
        XCTAssertTrue(session.isUnderlineActive)
        XCTAssertEqual(
            field.typingAttributes[.underlineStyle] as? Int,
            NSUnderlineStyle.single.rawValue
        )
        session.toggleUnderline()
        XCTAssertFalse(session.isUnderlineActive)
        XCTAssertNil(field.typingAttributes[.underlineStyle])

        // With a selection it still applies to the existing text
        engine.textStorage.setAttributedString(NSAttributedString(
            string: "Existing text", attributes: NotebookTextEngine.defaultAttributes
        ))
        field.setSelectedRange(NSRange(location: 0, length: 5))
        session.toggleBold()
        let applied = try XCTUnwrap(engine.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: applied).contains(.boldFontMask))
        XCTAssertTrue(session.isBoldActive, "With a selection the button shows the state of the text")

        session.toggleUnderline()
        XCTAssertEqual(
            engine.textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertTrue(session.isUnderlineActive)
    }

    func testAlignmentAppliesToWholeParagraphs() throws {
        let package = try NotebookPackage.create(title: "Alignment", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Alignment")
        let engine = session.textEngine

        let field = NSTextView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400),
            textContainer: engine.containers[0]
        )
        field.typingAttributes = NotebookTextEngine.defaultAttributes
        session.activeTextView = field

        engine.textStorage.setAttributedString(NSAttributedString(
            string: "First paragraph\nSecond paragraph",
            attributes: NotebookTextEngine.defaultAttributes
        ))

        XCTAssertEqual(session.currentAlignment, .left, "Left-aligned is the default")

        // Cursor in the middle of the first paragraph
        field.setSelectedRange(NSRange(location: 3, length: 0))
        session.setAlignment(.center)
        XCTAssertEqual(session.currentAlignment, .center)

        func alignment(at location: Int) -> NSTextAlignment? {
            (engine.textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil)
                as? NSParagraphStyle)?.alignment
        }
        XCTAssertEqual(alignment(at: 0), .center, "The whole paragraph, not just the cursor position")
        XCTAssertEqual(alignment(at: 14), .center)
        XCTAssertNotEqual(alignment(at: 20), .center, "The second paragraph stays unaffected")

        field.setSelectedRange(NSRange(location: 20, length: 0))
        session.setAlignment(.right)
        XCTAssertEqual(alignment(at: 20), .right)
        XCTAssertEqual(alignment(at: 0), .center)
    }

    func testTextAndFormattingSurviveSaving() throws {
        let package = try NotebookPackage.create(title: "RTF", at: workingDirectory)
        let engine = filledEngine(package, repeating: 5)
        engine.toggleTrait(.boldFontMask, in: NSRange(location: 0, length: 10))
        engine.toggleUnderline(in: NSRange(location: 0, length: 10))
        engine.setAlignment(.center, in: NSRange(location: 0, length: 1))
        package.setBodyRTF(engine.rtfData())
        try package.write()

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.url.appending(path: "body.rtf").path))

        let reopened = try NotebookPackage.read(from: package.url)
        let restored = NotebookTextEngine(rtf: reopened.bodyRTF)
        XCTAssertEqual(restored.textStorage.string, engine.textStorage.string)

        let font = try XCTUnwrap(restored.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertNotEqual(
            restored.textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 0,
            "Underline must survive the RTF round trip"
        )
        XCTAssertEqual(
            (restored.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle)?.alignment,
            .center,
            "Alignment must survive the RTF round trip"
        )
    }

    func testTextIsExportedAsRealText() throws {
        let package = try NotebookPackage.create(title: "Export", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let flattened = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertEqual(flattened.pageCount, package.pdf.pageCount)

        let first = flattened.page(at: 0)?.string ?? ""
        let second = flattened.page(at: 1)?.string ?? ""
        XCTAssertTrue(first.contains("A paragraph"), "Text must be extractable, not just pixels")
        XCTAssertGreaterThan(second.count, 100)
        XCTAssertNotEqual(first, second, "Pages must not carry the same text")
    }

    /// The regression from the dark mode bug: dynamic colors resolved to
    /// white on white paper.
    func testInkAndLineColorsAreNotWhite() throws {
        let package = try NotebookPackage.create(title: "Visible", at: workingDirectory)
        let engine = filledEngine(package, repeating: 20)

        let withText = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: withText), 1000, "Text is invisible")

        let empty = try NotebookPackage.create(title: "Empty", at: workingDirectory)
        let blank = try NotebookRenderer.flattened(empty)
        XCTAssertEqual(TestSupport.inkPixelCount(in: blank), 0)

        empty.setRuling(.lines)
        let lined = try NotebookRenderer.flattened(empty)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: lined), 1000, "Lines are invisible")

        empty.setRuling(.grid)
        let grid = try NotebookRenderer.flattened(empty)
        XCTAssertGreaterThan(
            TestSupport.inkPixelCount(in: grid),
            TestSupport.inkPixelCount(in: lined),
            "Grid must draw more than lines"
        )
    }

    func testAnnotationsSurviveFlattening() throws {
        let package = try NotebookPackage.create(title: "Annotated", at: workingDirectory)
        let before = try NotebookRenderer.flattened(package)
        let withoutAnnotation = TestSupport.inkPixelCount(in: before)

        let highlight = PDFAnnotation(
            bounds: CGRect(x: 80, y: 400, width: 300, height: 30),
            forType: .highlight, withProperties: nil
        )
        highlight.color = .systemYellow
        package.pdf.page(at: 0)?.addAnnotation(highlight)

        let after = try NotebookRenderer.flattened(package)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: after), withoutAnnotation)
    }

    func testTextFlowsPastImportedPages() throws {
        let package = try NotebookPackage.create(title: "Mixed", at: workingDirectory)
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "q.pdf"))
        try package.appendPages(fromPDFAt: source)
        try package.insertBlankPage()

        XCTAssertEqual(package.writablePageIndices, [0, 4])
        XCTAssertEqual(package.textAreaSizes().count, 2)
    }
}
