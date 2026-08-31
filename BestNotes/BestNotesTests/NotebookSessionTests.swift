//
//  NotebookSessionTests.swift
//  BestNotesTests
//

import AppKit
import PDFKit
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

        XCTAssertEqual(session.pageDescriptors.count, 1)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(session.notebookMode, .write)
    }

    func testSeitenWachsenBeimTippenNach() throws {
        let package = try NotebookPackage.create(title: "Wachstum", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Wachstum")
        let engine = session.textEngine

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
        let engine = session.textEngine

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
        longText(session.textEngine)
        session.growPagesIfNeeded()
        session.setRuling(.lines)

        try session.save()
        XCTAssertFalse(session.hasUnsavedChanges)

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url),
            name: "Dauerhaft"
        )
        XCTAssertEqual(reopened.pageDescriptors.count, session.pageDescriptors.count)
        XCTAssertEqual(reopened.textEngine.textStorage.string, session.textEngine.textStorage.string)
        XCTAssertEqual(reopened.ruling, .lines)
        XCTAssertFalse(reopened.textEngine.overflows)
    }

    func testAutosicherungSchreibtOhneZutun() throws {
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

    func testSeiteAmEndeOderHinterDerAktuellen() throws {
        let package = try NotebookPackage.create(title: "Einfuegen", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Einfuegen")
        session.insertBlankPage()
        session.insertBlankPage()
        let original = session.pageDescriptors.map(\.id)
        XCTAssertEqual(original.count, 3)

        // Hinter der aktuellen Seite
        session.setCurrentPage(0)
        session.insertBlankPage(after: session.currentPageIndex)
        XCTAssertEqual(session.pageDescriptors.count, 4)
        XCTAssertEqual(session.pageDescriptors[0].id, original[0])
        XCTAssertFalse(original.contains(session.pageDescriptors[1].id), "Die neue Seite steht an Position 2")
        XCTAssertEqual(session.pageDescriptors[2].id, original[1])

        // Am Ende
        let beforeAppend = session.pageDescriptors.map(\.id)
        session.insertBlankPage()
        XCTAssertEqual(session.pageDescriptors.count, 5)
        XCTAssertEqual(Array(session.pageDescriptors.prefix(4)).map(\.id), beforeAppend)
        XCTAssertEqual(session.pageDescriptors.last?.kind, .blank)
    }

    /// Beide Modi teilen sich die Seitenposition — beim Umschalten darf die
    /// Ansicht nicht wieder vorne anfangen.
    func testSeitenpositionUeberlebtDenModuswechsel() throws {
        let package = try NotebookPackage.create(title: "Position", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Position")
        for _ in 0..<4 { session.insertBlankPage() }
        XCTAssertEqual(session.pageDescriptors.count, 5)

        session.setCurrentPage(3)
        session.notebookMode = .annotate
        XCTAssertEqual(session.currentPageIndex, 3)
        session.notebookMode = .write
        XCTAssertEqual(session.currentPageIndex, 3, "Die Seite gehoert dem Dokument, nicht dem Modus")

        // Die PDFView meldet ihre Seite in denselben Wert
        session.reportPageIndex(1)
        XCTAssertEqual(session.currentPageIndex, 1)

        session.setCurrentPage(99)
        XCTAssertEqual(session.currentPageIndex, 4, "Ausserhalb wird geklemmt")
        session.setCurrentPage(-3)
        XCTAssertEqual(session.currentPageIndex, 0)
    }

    /// Der Kern der Vereinheitlichung: eine importierte PDF ist ein
    /// Notizbuch wie jedes andere — beschreibbar, erweiterbar, exportierbar.
    func testImportiertePDFVerhaeltSichWieEinNotizbuch() throws {
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "q.pdf"))
        let document = try XCTUnwrap(PDFDocument(url: source))
        let package = try NotebookPackage.create(
            title: "Skript", from: document, sourceName: "q.pdf", at: workingDirectory
        )
        let session = DocumentSession(package: package, name: "Skript")

        XCTAssertEqual(session.pageDescriptors.count, 3)
        XCTAssertTrue(session.pageDescriptors.allSatisfy { $0.kind == .imported })
        XCTAssertTrue(package.writablePageIndices.isEmpty, "Importierte Seiten tragen keinen Textfluss")

        // Leere Seite anhaengen und beschreiben
        session.insertBlankPage()
        XCTAssertEqual(session.pageDescriptors.count, 4)
        XCTAssertEqual(package.writablePageIndices, [3])

        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Eigene Notiz zum Skript.",
            attributes: NotebookTextEngine.defaultAttributes
        ))

        // Annotation auf einer importierten Seite
        let highlight = PDFAnnotation(
            bounds: CGRect(x: 60, y: 700, width: 200, height: 20),
            forType: .highlight, withProperties: nil
        )
        highlight.color = .systemYellow
        let page = try XCTUnwrap(package.pdf.page(at: 0))
        session.addAnnotations([highlight], on: page, actionName: "Markieren")

        try session.save()

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url), name: "Skript"
        )
        XCTAssertEqual(reopened.pageDescriptors.count, 4)
        XCTAssertEqual(reopened.textEngine.textStorage.string, "Eigene Notiz zum Skript.")
        XCTAssertEqual(reopened.document.page(at: 0)?.annotations.count, 1)

        let flattened = try NotebookRenderer.flattened(reopened.notebook, engine: reopened.textEngine)
        XCTAssertEqual(flattened.pageCount, 4)
        XCTAssertTrue((flattened.page(at: 0)?.string ?? "").contains("Testseite 1"), "Originalseite bleibt")
        XCTAssertTrue((flattened.page(at: 3)?.string ?? "").contains("Eigene Notiz"), "Eigener Text kommt mit")
    }

    func testEingefuegteSeiteNimmtAmTextflussTeil() throws {
        // Eine Seite mitten im Fluss kann nicht leer bleiben — der Text
        // rueckt nach, wie beim Einfuegen einer Seite in einer Textverarbeitung.
        let package = try NotebookPackage.create(title: "Fluss", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Fluss")
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
        XCTAssertGreaterThanOrEqual(all.count, expected - 5, "Beim Umbruch ist Text verlorengegangen")
    }
}
