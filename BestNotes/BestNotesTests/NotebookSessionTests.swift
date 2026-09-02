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

    /// Der getippte Text liegt in body.rtf, die Annotationsansicht zeigt
    /// aber content.pdf — dort muss er beim Umschalten auftauchen.
    func testTextErscheintImAnnotationsmodusInDerSeite() throws {
        let package = try NotebookPackage.create(title: "Sichtbar", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Sichtbar")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Diese Zeile muss auch beim Annotieren zu sehen sein.",
            attributes: NotebookTextEngine.defaultAttributes
        ))

        XCTAssertEqual(TestSupport.inkPixelCount(in: package.pdf), 0, "Im Schreibmodus ist die Seite leer")

        session.notebookMode = .annotate
        // Eine Zeile Text ergibt ein paar hundert Pixel; entscheidend ist der
        // Unterschied zur leeren Seite, nicht der genaue Wert.
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: package.pdf), 100, "Der Text fehlt in der Seite")
        XCTAssertTrue(
            (package.pdf.page(at: 0)?.string ?? "").contains("auch beim Annotieren"),
            "Als echter Text, damit Markieren funktioniert"
        )

        session.notebookMode = .write
        XCTAssertEqual(TestSupport.inkPixelCount(in: package.pdf), 0, "Sonst stuende der Text doppelt da")
    }

    func testAnnotationenUeberlebenDenSeitentausch() throws {
        let package = try NotebookPackage.create(title: "Annotiert", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Annotiert")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Text", attributes: NotebookTextEngine.defaultAttributes
        ))

        session.notebookMode = .annotate
        let ink = PDFAnnotation(
            bounds: try XCTUnwrap(package.pdf.page(at: 0)).bounds(for: .cropBox),
            forType: .ink, withProperties: nil
        )
        ink.color = .red
        session.addAnnotations([ink], on: try XCTUnwrap(package.pdf.page(at: 0)), actionName: "Freihand")
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)

        session.notebookMode = .write
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1, "Beim Zuruecktauschen verloren")

        session.notebookMode = .annotate
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)
    }

    /// Eine gespeicherte Fassung mit eingebranntem Text darf im Schreibmodus
    /// nicht doppelt erscheinen.
    func testEingebrannterTextWirdBeimOeffnenEntfernt() throws {
        let package = try NotebookPackage.create(title: "Doppelt", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Doppelt")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: "Gespeichert im Annotationsmodus.",
            attributes: NotebookTextEngine.defaultAttributes
        ))
        session.notebookMode = .annotate
        try session.save()
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: package.pdf), 100)

        let reopened = DocumentSession(
            package: try NotebookPackage.read(from: package.url), name: "Doppelt"
        )
        XCTAssertEqual(reopened.notebookMode, .write)
        XCTAssertEqual(TestSupport.inkPixelCount(in: reopened.notebook.pdf), 0)
        XCTAssertEqual(reopened.textEngine.textStorage.string, "Gespeichert im Annotationsmodus.")
    }

    /// „Die Zettel werden nicht gespeichert“ — das darf nicht passieren,
    /// auch nicht ueber einen Moduswechsel hinweg.
    func testZettelUeberlebtModuswechselUndSichern() throws {
        let package = try NotebookPackage.create(title: "Zettel", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Zettel")
        session.notebookMode = .annotate

        let page = try XCTUnwrap(package.pdf.page(at: 0))
        let note = PDFAnnotation(
            bounds: CGRect(x: 60, y: 600, width: 180, height: 90),
            forType: .freeText, withProperties: nil
        )
        note.contents = "Nicht verlieren"
        note.color = NSColor(calibratedRed: 1, green: 0.9, blue: 0.55, alpha: 1)
        note.fontColor = .black
        note.font = .systemFont(ofSize: 13)
        session.addAnnotations([note], on: page, actionName: "Zettel")

        // Hin und her schalten tauscht die Seiten aus
        session.notebookMode = .write
        session.notebookMode = .annotate
        XCTAssertEqual(package.pdf.page(at: 0)?.annotations.count, 1)

        try session.save()

        let reopened = try NotebookPackage.read(from: package.url)
        let restored = try XCTUnwrap(reopened.pdf.page(at: 0)?.annotations.first)
        XCTAssertEqual(restored.type, "FreeText")
        XCTAssertEqual(restored.contents, "Nicht verlieren")
        XCTAssertEqual(restored.bounds.origin.x, 60, accuracy: 0.5)
    }

    func testZettelBewegenUndBeschriftenLassenSichWiderrufen() throws {
        let package = try NotebookPackage.create(title: "Zettel", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Zettel")
        session.undoManager.groupsByEvent = false
        let page = try XCTUnwrap(package.pdf.page(at: 0))

        let note = PDFAnnotation(
            bounds: CGRect(x: 60, y: 600, width: 180, height: 90),
            forType: .freeText, withProperties: nil
        )
        note.contents = ""
        TestSupport.undoGroup(session.undoManager) {
            session.addAnnotations([note], on: page, actionName: "Zettel")
        }

        TestSupport.undoGroup(session.undoManager) {
            note.contents = "Erste Fassung"
            session.noteEdited(note, on: page, from: "")
        }
        XCTAssertEqual(page.annotations.first?.contents, "Erste Fassung")

        let moved = CGRect(x: 200, y: 400, width: 180, height: 90)
        TestSupport.undoGroup(session.undoManager) {
            note.bounds = moved
            session.noteMoved(note, on: page, from: CGRect(x: 60, y: 600, width: 180, height: 90))
        }
        XCTAssertEqual(note.bounds, moved)

        session.undo()
        XCTAssertEqual(note.bounds.origin.y, 600, "Bewegung nicht widerrufen")
        XCTAssertEqual(note.contents, "Erste Fassung", "Der Text darf dabei bleiben")

        session.undo()
        XCTAssertEqual(note.contents, "", "Beschriftung nicht widerrufen")

        session.redo()
        XCTAssertEqual(note.contents, "Erste Fassung")
    }

    /// Im Annotationsmodus steckt der Text in den Seiten. Kommt eine Seite
    /// dazu, fliesst er um — die eingebrannte Fassung muss nachziehen.
    func testSeiteEinfuegenImAnnotationsmodusBrenntNeu() throws {
        let package = try NotebookPackage.create(title: "Umbruch", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Umbruch")
        session.textEngine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Fliesstext ueber mehrere Seiten. ", count: 200),
            attributes: NotebookTextEngine.defaultAttributes
        ))
        session.growPagesIfNeeded()
        session.notebookMode = .annotate

        let before = (0..<package.pdf.pageCount)
            .compactMap { package.pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(before.contains("Fliesstext"))

        session.setCurrentPage(0)
        session.insertBlankPage(after: 0)

        let after = (0..<package.pdf.pageCount)
            .compactMap { package.pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(after.contains("Fliesstext"), "Nach dem Einfuegen fehlt der eingebrannte Text")
        XCTAssertGreaterThanOrEqual(
            after.replacingOccurrences(of: " ", with: "").count,
            before.replacingOccurrences(of: " ", with: "").count - 5,
            "Beim Neubrennen ist Text verlorengegangen"
        )
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
