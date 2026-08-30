//
//  NotebookSessionTests.swift
//  BestNotesTests
//

import AppKit
import XCTest
@testable import BestNotes

@MainActor
final class NotebookSessionTests: TemporaryDirectoryTestCase {

    private func longText(_ engine: NotebookTextEngine, count: Int = 400) {
        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Mitschrift mit reichlich Inhalt. ", count: count),
            attributes: NotebookTextEngine.defaultAttributes
        ))
    }

    func testFrischeSitzung() throws {
        let package = try NotebookPackage.create(title: "Vorlesung", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Vorlesung")

        XCTAssertNotNil(session.notebook)
        XCTAssertNotNil(session.textEngine)
        XCTAssertEqual(session.pageDescriptors.count, 1)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(session.notebookMode, .write)
    }

    func testSeitenWachsenBeimTippenNach() throws {
        let package = try NotebookPackage.create(title: "Wachstum", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Wachstum")
        let engine = try XCTUnwrap(session.textEngine)

        longText(engine)
        XCTAssertTrue(session.hasUnsavedChanges, "Tippen muss als Aenderung zaehlen")

        session.growPagesIfNeeded()
        XCTAssertGreaterThan(session.pageDescriptors.count, 1)
        XCTAssertFalse(engine.overflows)
        XCTAssertEqual(engine.containers.count, package.writablePageIndices.count)
    }

    func testSeiteEinfuegenUndLoeschen() throws {
        let package = try NotebookPackage.create(title: "Seiten", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Seiten")
        let engine = try XCTUnwrap(session.textEngine)

        session.insertBlankPage(after: 0)
        XCTAssertEqual(session.pageDescriptors.count, 2)
        XCTAssertEqual(session.pageDescriptors[1].kind, .blank)
        XCTAssertEqual(engine.containers.count, 2)

        session.removePage(at: 1)
        XCTAssertEqual(session.pageDescriptors.count, 1)
        XCTAssertEqual(engine.containers.count, 1)

        session.removePage(at: 0)
        XCTAssertEqual(session.pageDescriptors.count, 1, "Die letzte Seite darf nicht verschwinden")
    }

    func testSichernUndNeuOeffnen() throws {
        let package = try NotebookPackage.create(title: "Dauerhaft", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Dauerhaft")
        longText(try XCTUnwrap(session.textEngine))
        session.growPagesIfNeeded()
        session.setRuling(.lines)

        try session.save()
        XCTAssertFalse(session.hasUnsavedChanges)

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url),
            name: "Dauerhaft"
        )
        XCTAssertEqual(reopened.pageDescriptors.count, session.pageDescriptors.count)
        XCTAssertEqual(reopened.textEngine?.textStorage.string, session.textEngine?.textStorage.string)
        XCTAssertEqual(reopened.ruling, .lines)
        XCTAssertEqual(reopened.textEngine?.overflows, false)
    }

    func testAutosicherungSchreibtOhneZutun() throws {
        let package = try NotebookPackage.create(title: "Auto", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Auto")
        longText(try XCTUnwrap(session.textEngine), count: 5)

        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(session.saveQuietly())
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(session.saveError)

        let reopened = try NotebookPackage.read(from: package.url)
        XCTAssertNotNil(reopened.bodyRTF)
    }

    func testEingefuegteSeiteNimmtAmTextflussTeil() throws {
        // Eine Seite mitten im Fluss kann nicht leer bleiben — der Text
        // rueckt nach, wie beim Einfuegen einer Seite in einer Textverarbeitung.
        let package = try NotebookPackage.create(title: "Fluss", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Fluss")
        let engine = try XCTUnwrap(session.textEngine)
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
        XCTAssertGreaterThanOrEqual(all.count, expected - 5, "Beim Umbruch ist Text verlorengegangen")
    }
}
