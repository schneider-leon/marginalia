//
//  NotebookSessionTests.swift
//  marginaliaTests
//

import AppKit
import PDFKit
import XCTest
@testable import marginalia

@MainActor
final class NotebookSessionTests: TemporaryDirectoryTestCase {

    private func longText(_ engine: NotebookTextEngine, count: Int = 400) {
        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Lecture notes with plenty of content. ", count: count),
            attributes: NotebookTextEngine.defaultAttributes
        ))
    }

    func testFreshSession() throws {
        let package = try NotebookPackage.create(title: "Lecture", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Lecture")

        XCTAssertEqual(session.pageDescriptors.count, 1)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(session.notebookMode, .write)
    }

    func testPagesGrowWhileTyping() throws {
        let package = try NotebookPackage.create(title: "Growth", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Growth")
        let engine = session.textEngine

        longText(engine)
        XCTAssertTrue(session.hasUnsavedChanges, "Typing must count as a change")

        session.growPagesIfNeeded()
        XCTAssertGreaterThan(session.pageDescriptors.count, 1)
        XCTAssertFalse(engine.overflows)
        XCTAssertEqual(engine.containers.count, package.writablePageIndices.count)
    }

    func testInsertingAndDeletingPages() throws {
        let package = try NotebookPackage.create(title: "Pages", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Pages")
        let engine = session.textEngine

        session.insertBlankPage(after: 0)
        XCTAssertEqual(session.pageDescriptors.count, 2)
        XCTAssertEqual(session.pageDescriptors[1].kind, .blank)
        XCTAssertEqual(engine.containers.count, 2)

        session.removePage(at: 1)
        XCTAssertEqual(session.pageDescriptors.count, 1)
        XCTAssertEqual(engine.containers.count, 1)

        session.removePage(at: 0)
        XCTAssertEqual(session.pageDescriptors.count, 1, "The last page must not disappear")
    }

    func testSavingAndReopening() throws {
        let package = try NotebookPackage.create(title: "Persistent", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Persistent")
        longText(session.textEngine)
        session.growPagesIfNeeded()
        session.setRuling(.lines)

        try session.save()
        XCTAssertFalse(session.hasUnsavedChanges)

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url),
            name: "Persistent"
        )
        XCTAssertEqual(reopened.pageDescriptors.count, session.pageDescriptors.count)
        XCTAssertEqual(reopened.textEngine.textStorage.string, session.textEngine.textStorage.string)
        XCTAssertEqual(reopened.ruling, .lines)
        XCTAssertFalse(reopened.textEngine.overflows)
    }

    func testAutosaveWritesWithoutHelp() throws {
        let package = try NotebookPackage.create(title: "Auto", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Auto")
        longText(session.textEngine, count: 5)

        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(session.saveQuietly())
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(session.saveError)

        let reopened = try NotebookPackage.read(from: package.url)
        XCTAssertNotNil(reopened.bodyRTF)
    }

    func testPageAtTheEndOrAfterTheCurrentOne() throws {
        let package = try NotebookPackage.create(title: "Insert", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Insert")
        session.insertBlankPage()
        session.insertBlankPage()
        let original = session.pageDescriptors.map(\.id)
        XCTAssertEqual(original.count, 3)

        // After the current page
        session.setCurrentPage(0)
        session.insertBlankPage(after: session.currentPageIndex)
        XCTAssertEqual(session.pageDescriptors.count, 4)
        XCTAssertEqual(session.pageDescriptors[0].id, original[0])
        XCTAssertFalse(original.contains(session.pageDescriptors[1].id), "The new page is at position 2")
        XCTAssertEqual(session.pageDescriptors[2].id, original[1])

        // At the end
        let beforeAppend = session.pageDescriptors.map(\.id)
        session.insertBlankPage()
        XCTAssertEqual(session.pageDescriptors.count, 5)
        XCTAssertEqual(Array(session.pageDescriptors.prefix(4)).map(\.id), beforeAppend)
        XCTAssertEqual(session.pageDescriptors.last?.kind, .blank)
    }

    /// The typed text lives in body.rtf, but the annotation view shows
    /// content.pdf — it has to show up there when switching.
    func testTextAppearsInThePageInAnnotationMode() throws {
        let package = try NotebookPackage.create(title: "Visible", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Visible")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "This line must be visible while annotating too.",
            attributes: NotebookTextEngine.defaultAttributes
        ))

        XCTAssertEqual(TestSupport.inkPixelCount(in: package.pdf), 0, "In writing mode the page is empty")

        session.notebookMode = .annotate
        // One line of text yields a few hundred pixels; what matters is the
        // difference to the empty page, not the exact value.
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: package.pdf), 100, "The text is missing from the page")
        XCTAssertTrue(
            (package.pdf.page(at: 0)?.string ?? "").contains("while annotating too"),
            "As real text, so highlighting works"
        )

        session.notebookMode = .write
        XCTAssertEqual(TestSupport.inkPixelCount(in: package.pdf), 0, "Otherwise the text would appear twice")
    }

    func testAnnotationsSurvivePageSwap() throws {
        let package = try NotebookPackage.create(title: "Annotated", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Annotated")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Text", attributes: NotebookTextEngine.defaultAttributes
        ))

        session.notebookMode = .annotate
        let ink = PDFAnnotation(
            bounds: try XCTUnwrap(package.pdf.page(at: 0)).bounds(for: .cropBox),
            forType: .ink, withProperties: nil
        )
        ink.color = .red
        session.addAnnotations([ink], on: try XCTUnwrap(package.pdf.page(at: 0)), actionName: "Freehand")
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)

        session.notebookMode = .write
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1, "Lost when swapping back")

        session.notebookMode = .annotate
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)
    }

    /// A saved version with burned-in text must not appear twice in writing
    /// mode.
    func testBurnedInTextIsRemovedOnOpen() throws {
        let package = try NotebookPackage.create(title: "Twice", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Twice")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Saved in annotation mode.",
            attributes: NotebookTextEngine.defaultAttributes
        ))
        session.notebookMode = .annotate
        try session.save()
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: package.pdf), 100)

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url), name: "Twice"
        )
        XCTAssertEqual(reopened.notebookMode, .write)
        XCTAssertEqual(TestSupport.inkPixelCount(in: reopened.notebook.pdf), 0)
        XCTAssertEqual(reopened.textEngine.textStorage.string, "Saved in annotation mode.")
    }

    /// "The sticky notes are not saved" — that must not happen, not even
    /// across a mode switch.
    func testNoteSurvivesModeSwitchAndSaving() throws {
        let package = try NotebookPackage.create(title: "Note", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Note")
        session.notebookMode = .annotate

        let page = try XCTUnwrap(package.pdf.page(at: 0))
        let note = PDFAnnotation(
            bounds: CGRect(x: 60, y: 600, width: 180, height: 90),
            forType: .freeText, withProperties: nil
        )
        note.contents = "Do not lose"
        note.color = NSColor(calibratedRed: 1, green: 0.9, blue: 0.55, alpha: 1)
        note.fontColor = .black
        note.font = .systemFont(ofSize: 13)
        session.addAnnotations([note], on: page, actionName: "Sticky Note")

        // Switching back and forth swaps the pages
        session.notebookMode = .write
        session.notebookMode = .annotate
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)

        try session.save()

        let reopened = try NotebookPackage.read(from: package.url)
        let restored = try XCTUnwrap(reopened.pdf.page(at: 0)?.annotations.first)
        XCTAssertEqual(restored.type, "FreeText")
        XCTAssertEqual(restored.contents, "Do not lose")
        XCTAssertEqual(restored.bounds.origin.x, 60, accuracy: 0.5)
    }

    func testMovingAndEditingNotesCanBeUndone() throws {
        let package = try NotebookPackage.create(title: "Note", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Note")
        session.undoManager.groupsByEvent = false
        let page = try XCTUnwrap(package.pdf.page(at: 0))

        let note = PDFAnnotation(
            bounds: CGRect(x: 60, y: 600, width: 180, height: 90),
            forType: .freeText, withProperties: nil
        )
        note.contents = ""
        TestSupport.undoGroup(session.undoManager) {
            session.addAnnotations([note], on: page, actionName: "Sticky Note")
        }

        TestSupport.undoGroup(session.undoManager) {
            note.contents = "First draft"
            session.noteEdited(note, on: page, from: "")
        }
        XCTAssertEqual(page.annotations.first?.contents, "First draft")

        let moved = CGRect(x: 200, y: 400, width: 180, height: 90)
        TestSupport.undoGroup(session.undoManager) {
            note.bounds = moved
            session.noteMoved(note, on: page, from: CGRect(x: 60, y: 600, width: 180, height: 90))
        }
        XCTAssertEqual(note.bounds, moved)

        session.undo()
        XCTAssertEqual(note.bounds.origin.y, 600, "Move not undone")
        XCTAssertEqual(note.contents, "First draft", "The text may stay")

        session.undo()
        XCTAssertEqual(note.contents, "", "Text edit not undone")

        session.redo()
        XCTAssertEqual(note.contents, "First draft")
    }

    /// In annotation mode the text lives in the pages. When a page is added
    /// it reflows — the burned-in version has to follow.
    func testInsertingAPageInAnnotationModeReburns() throws {
        let package = try NotebookPackage.create(title: "Reflow", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Reflow")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Running text across several pages. ", count: 200),
            attributes: NotebookTextEngine.defaultAttributes
        ))
        session.growPagesIfNeeded()
        session.notebookMode = .annotate

        let before = (0..<package.pdf.pageCount)
            .compactMap { package.pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(before.contains("Running text"))

        session.setCurrentPage(0)
        session.insertBlankPage(after: 0)

        let after = (0..<package.pdf.pageCount)
            .compactMap { package.pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(after.contains("Running text"), "The burned-in text is missing after inserting")
        XCTAssertGreaterThanOrEqual(
            after.replacingOccurrences(of: " ", with: "").count,
            before.replacingOccurrences(of: " ", with: "").count - 5,
            "Text was lost while reburning"
        )
    }

    /// Both modes share the page position — the view must not start at the
    /// front again when switching.
    func testPagePositionSurvivesModeSwitch() throws {
        let package = try NotebookPackage.create(title: "Position", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Position")
        for _ in 0..<4 { session.insertBlankPage() }
        XCTAssertEqual(session.pageDescriptors.count, 5)

        session.setCurrentPage(3)
        session.notebookMode = .annotate
        XCTAssertEqual(session.currentPageIndex, 3)
        session.notebookMode = .write
        XCTAssertEqual(session.currentPageIndex, 3, "The page belongs to the document, not to the mode")

        // The PDFView reports its page into the same value
        session.reportPageIndex(1)
        XCTAssertEqual(session.currentPageIndex, 1)

        session.setCurrentPage(99)
        XCTAssertEqual(session.currentPageIndex, 4, "Out-of-range values are clamped")
        session.setCurrentPage(-3)
        XCTAssertEqual(session.currentPageIndex, 0)
    }

    /// The core of the unification: an imported PDF is a notebook like any
    /// other — writable, extendable, exportable.
    func testImportedPDFBehavesLikeANotebook() throws {
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "q.pdf"))
        let document = try XCTUnwrap(PDFDocument(url: source))
        let package = try NotebookPackage.create(
            title: "Script", from: document, sourceName: "q.pdf", at: workingDirectory
        )
        let session = DocumentSession(package: package, name: "Script")

        XCTAssertEqual(session.pageDescriptors.count, 3)
        XCTAssertTrue(session.pageDescriptors.allSatisfy { $0.kind == .imported })
        XCTAssertTrue(package.writablePageIndices.isEmpty, "Imported pages carry no text flow")

        // Append a blank page and write on it
        session.insertBlankPage()
        XCTAssertEqual(session.pageDescriptors.count, 4)
        XCTAssertEqual(package.writablePageIndices, [3])

        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "My own note on the script.",
            attributes: NotebookTextEngine.defaultAttributes
        ))

        // Annotation on an imported page
        let highlight = PDFAnnotation(
            bounds: CGRect(x: 60, y: 700, width: 200, height: 20),
            forType: .highlight, withProperties: nil
        )
        highlight.color = .systemYellow
        let page = try XCTUnwrap(package.pdf.page(at: 0))
        session.addAnnotations([highlight], on: page, actionName: "Highlight")

        try session.save()

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url), name: "Script"
        )
        XCTAssertEqual(reopened.pageDescriptors.count, 4)
        XCTAssertEqual(reopened.textEngine.textStorage.string, "My own note on the script.")
        XCTAssertEqual(reopened.document.page(at: 0)?.annotations.count, 1)

        let flattened = try NotebookRenderer.flattened(reopened.notebook, engine: reopened.textEngine)
        XCTAssertEqual(flattened.pageCount, 4)
        XCTAssertTrue((flattened.page(at: 0)?.string ?? "").contains("Test page 1"), "The original page stays")
        XCTAssertTrue((flattened.page(at: 3)?.string ?? "").contains("My own note"), "Own text comes along")
    }

    func testInsertedPageTakesPartInTextFlow() throws {
        // A page in the middle of the flow cannot stay empty — the text
        // moves up, as when inserting a page in a word processor.
        let package = try NotebookPackage.create(title: "Flow", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Flow")
        let engine = session.textEngine
        longText(engine)
        session.growPagesIfNeeded()
        session.insertBlankPage(after: 0)

        let flattened = try NotebookRenderer.flattened(package, engine: engine)
        let second = (flattened.page(at: 1)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(second.isEmpty)

        let all = (0..<flattened.pageCount)
            .compactMap { flattened.page(at: $0)?.string }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let expected = engine.textStorage.string.replacingOccurrences(of: " ", with: "").count
        XCTAssertGreaterThanOrEqual(all.count, expected - 5, "Text was lost while reflowing")
    }
}
