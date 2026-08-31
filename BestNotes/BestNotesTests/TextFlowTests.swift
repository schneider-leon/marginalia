//
//  TextFlowTests.swift
//  BestNotesTests
//

import AppKit
import PDFKit
import XCTest
@testable import BestNotes

@MainActor
final class TextFlowTests: TemporaryDirectoryTestCase {

    private func filledEngine(_ package: NotebookPackage, repeating count: Int) -> NotebookTextEngine {
        let engine = NotebookTextEngine()
        engine.updateContainers(sizes: package.textAreaSizes())
        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Ein Absatz mit genug Text, um die Seite zu fuellen. ", count: count),
            attributes: NotebookTextEngine.defaultAttributes
        ))
        return engine
    }

    func testSchreibflaecheIstSeiteMinusRand() throws {
        let package = try NotebookPackage.create(title: "Rand", at: workingDirectory)
        XCTAssertEqual(package.writablePageIndices, [0])
        XCTAssertEqual(
            package.textAreaSizes().first,
            CGSize(width: 595 - 112, height: 842 - 112)
        )
    }

    func testTextLaeuftUeberUndBrauchtMehrSeiten() throws {
        let package = try NotebookPackage.create(title: "Fluss", at: workingDirectory)
        let area = try XCTUnwrap(package.textAreaSizes().first)

        let engine = filledEngine(package, repeating: 3)
        XCTAssertFalse(engine.overflows)
        XCTAssertEqual(engine.requiredPageCount(pageSize: area), 1)

        engine.textStorage.setAttributedString(NSAttributedString(
            string: String(repeating: "Ein Absatz mit genug Text, um die Seite zu fuellen. ", count: 300),
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

    func testSeitenSetzenEinanderFort() throws {
        let package = try NotebookPackage.create(title: "Fortsetzung", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let first = try XCTUnwrap(engine.glyphRange(forContainerAt: 0))
        let second = try XCTUnwrap(engine.glyphRange(forContainerAt: 1))
        XCTAssertGreaterThan(first.length, 0)
        XCTAssertGreaterThan(second.length, 0)
        XCTAssertEqual(second.location, NSMaxRange(first), "Seite 2 muss hinter Seite 1 ansetzen")
    }

    func testEinfuegenAmAnfangSchiebtDenRestNachHinten() throws {
        let package = try NotebookPackage.create(title: "Schieben", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let before = try XCTUnwrap(engine.glyphRange(forContainerAt: 0)).length
        engine.textStorage.insert(NSAttributedString(
            string: String(repeating: "Neu am Anfang. ", count: 40),
            attributes: NotebookTextEngine.defaultAttributes
        ), at: 0)
        let after = try XCTUnwrap(engine.glyphRange(forContainerAt: 0)).length

        XCTAssertNotEqual(before, after)
        XCTAssertTrue(engine.overflows, "Der Text muss ueber die letzte Seite hinauslaufen")
    }

    /// Ohne Auswahl muss der Umschalter das *naechste* Getippte betreffen —
    /// sonst laesst sich fett nur nachtraeglich setzen.
    func testFettUndKursivOhneAuswahlWirkenAufsWeitereTippen() throws {
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
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Fett darf dabei nicht abfallen")

        // Der Zustand muss sich auch ablesen lassen, sonst kann die Leiste
        // ihn nicht anzeigen.
        XCTAssertTrue(session.isBoldActive)
        XCTAssertTrue(session.isItalicActive)

        session.setFontSize(24)
        font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.pointSize, 24)
        XCTAssertEqual(session.currentFontSize, 24)

        session.toggleBold()
        font = try XCTUnwrap(field.typingAttributes[.font] as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Erneutes Umschalten nimmt es zurueck")
        XCTAssertFalse(session.isBoldActive)
        XCTAssertTrue(session.isItalicActive, "Kursiv bleibt davon unberuehrt")

        // Mit Auswahl geht es weiterhin an den vorhandenen Text
        engine.textStorage.setAttributedString(NSAttributedString(
            string: "Vorhandener Text", attributes: NotebookTextEngine.defaultAttributes
        ))
        field.setSelectedRange(NSRange(location: 0, length: 5))
        session.toggleBold()
        let applied = try XCTUnwrap(engine.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: applied).contains(.boldFontMask))
        XCTAssertTrue(session.isBoldActive, "Bei Auswahl zeigt der Knopf den Zustand des Texts")
    }

    func testTextUndFormatUeberlebenDasSichern() throws {
        let package = try NotebookPackage.create(title: "RTF", at: workingDirectory)
        let engine = filledEngine(package, repeating: 5)
        engine.toggleTrait(.boldFontMask, in: NSRange(location: 0, length: 10))
        package.setBodyRTF(engine.rtfData())
        try package.write()

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.url.appending(path: "body.rtf").path))

        let reopened = try NotebookPackage.read(from: package.url)
        let restored = NotebookTextEngine(rtf: reopened.bodyRTF)
        XCTAssertEqual(restored.textStorage.string, engine.textStorage.string)

        let font = try XCTUnwrap(restored.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testTextWirdAlsEchterTextExportiert() throws {
        let package = try NotebookPackage.create(title: "Export", at: workingDirectory)
        try package.insertBlankPage()
        let engine = filledEngine(package, repeating: 300)

        let flattened = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertEqual(flattened.pageCount, package.pdf.pageCount)

        let first = flattened.page(at: 0)?.string ?? ""
        let second = flattened.page(at: 1)?.string ?? ""
        XCTAssertTrue(first.contains("Ein Absatz"), "Text muss auslesbar sein, nicht nur Pixel")
        XCTAssertGreaterThan(second.count, 100)
        XCTAssertNotEqual(first, second, "Seiten duerfen nicht denselben Text tragen")
    }

    /// Die Regression aus dem Dunkelmodus-Fehler: dynamische Farben loesten
    /// auf weissem Papier zu Weiss auf.
    func testTintenUndLinienfarbeSindNichtWeiss() throws {
        let package = try NotebookPackage.create(title: "Sichtbar", at: workingDirectory)
        let engine = filledEngine(package, repeating: 20)

        let withText = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: withText), 1000, "Text ist unsichtbar")

        let empty = try NotebookPackage.create(title: "Leer", at: workingDirectory)
        let blank = try NotebookRenderer.flattened(empty)
        XCTAssertEqual(TestSupport.inkPixelCount(in: blank), 0)

        empty.setRuling(.lines)
        let lined = try NotebookRenderer.flattened(empty)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: lined), 1000, "Linien sind unsichtbar")

        empty.setRuling(.grid)
        let grid = try NotebookRenderer.flattened(empty)
        XCTAssertGreaterThan(
            TestSupport.inkPixelCount(in: grid),
            TestSupport.inkPixelCount(in: lined),
            "Karo muss mehr zeichnen als Linien"
        )
    }

    func testAnnotationenUeberlebenDasEinbrennen() throws {
        let package = try NotebookPackage.create(title: "Annotiert", at: workingDirectory)
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

    func testTextFliesstAnImportiertenSeitenVorbei() throws {
        let package = try NotebookPackage.create(title: "Gemischt", at: workingDirectory)
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "q.pdf"))
        try package.appendPages(fromPDFAt: source)
        try package.insertBlankPage()

        XCTAssertEqual(package.writablePageIndices, [0, 4])
        XCTAssertEqual(package.textAreaSizes().count, 2)
    }
}
