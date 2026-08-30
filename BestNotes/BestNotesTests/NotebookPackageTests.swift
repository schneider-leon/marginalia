//
//  NotebookPackageTests.swift
//  BestNotesTests
//

import PDFKit
import XCTest
@testable import BestNotes

@MainActor
final class NotebookPackageTests: TemporaryDirectoryTestCase {

    func testNeuesPaketLiegtVollstaendigAufDerPlatte() throws {
        let package = try NotebookPackage.create(title: "Analysis II", at: workingDirectory)

        XCTAssertEqual(package.url.pathExtension, "bestnote")
        for component in ["info.json", "content.pdf", "overlays.json", "assets"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: package.url.appending(path: component).path),
                "\(component) fehlt"
            )
        }
        XCTAssertEqual(package.pageCount, 1)
        XCTAssertEqual(package.pdf.pageCount, 1)
        XCTAssertEqual(package.preferredPageSize, PDFPageFactory.a4)
    }

    func testSeitenImportUndLeerseite() throws {
        let package = try NotebookPackage.create(title: "Gemischt", at: workingDirectory)
        let source = try TestSupport.makeSamplePDF(
            pages: 6, at: workingDirectory.appending(path: "quelle.pdf")
        )

        let imported = try package.appendPages(fromPDFAt: source)
        XCTAssertEqual(imported.count, 6)
        XCTAssertEqual(package.pageCount, 7)
        XCTAssertEqual(imported.first?.source, "quelle.pdf")
        XCTAssertEqual(package.pdf.pageCount, package.info.pages.count)

        let blank = try package.insertBlankPage(at: 1)
        XCTAssertEqual(package.info.pages[1].id, blank.id)
        XCTAssertEqual(package.info.pages[1].kind, .blank)
        XCTAssertEqual(package.pdf.pageCount, 8)
        XCTAssertEqual(package.writablePageIndices, [0, 1])
    }

    func testSchreibenUndWiederLesen() throws {
        let package = try NotebookPackage.create(title: "Analysis II", at: workingDirectory)
        let pageID = try XCTUnwrap(package.pageID(at: 0))
        let asset = package.addAsset(data: Data([0x89, 0x50, 0x4E, 0x47]), fileExtension: "png")

        package.overlays[pageID] = [
            Overlay(frame: CGRect(x: 40, y: 700, width: 300, height: 40), zIndex: 1,
                    content: .text(TextOverlayContent(string: "Ueberschrift", fontSize: 24))),
            Overlay(frame: CGRect(x: 40, y: 400, width: 200, height: 150), zIndex: 0,
                    content: .image(ImageOverlayContent(assetName: asset)))
        ]
        package.setTitle("Analysis II — WS")
        try package.write()

        let reopened = try NotebookPackage.read(from: package.url)
        XCTAssertEqual(reopened.title, "Analysis II — WS")
        XCTAssertTrue(reopened.loadWarnings.isEmpty)
        XCTAssertEqual(reopened.overlays[pageID].count, 2)
        XCTAssertEqual(reopened.overlays.sortedOverlays(for: pageID).first?.zIndex, 0)
        XCTAssertEqual(reopened.overlays.sortedOverlays(for: pageID).last?.frame.origin.y, 700)
        XCTAssertEqual(reopened.assetData(named: asset)?.count, 4)

        guard case .text(let text)? = reopened.overlays.sortedOverlays(for: pageID).last?.content else {
            return XCTFail("Text-Overlay fehlt")
        }
        XCTAssertEqual(text.string, "Ueberschrift")
        XCTAssertEqual(text.fontSize, 24)
    }

    func testJSONIstLesbarUndVersioniert() throws {
        let package = try NotebookPackage.create(title: "Lesbar", at: workingDirectory)
        let info = try String(contentsOf: package.url.appending(path: "info.json"), encoding: .utf8)
        XCTAssertTrue(info.contains("\"title\""))
        XCTAssertTrue(info.contains("\"schemaVersion\""))

        let pageID = try XCTUnwrap(package.pageID(at: 0))
        package.overlays[pageID] = [
            Overlay(frame: CGRect(x: 1, y: 2, width: 3, height: 4),
                    content: .text(TextOverlayContent(string: "x")))
        ]
        try package.write()
        let overlays = try String(contentsOf: package.url.appending(path: "overlays.json"), encoding: .utf8)

        // Eigene Kodierung statt der synthetisierten: benannte Rahmenfelder
        // und ein type-Diskriminator, kein "_0".
        XCTAssertTrue(overlays.contains("\"type\" : \"text\""))
        XCTAssertTrue(overlays.contains("\"width\""))
        XCTAssertFalse(overlays.contains("_0"))
    }

    func testZweitesSchreibenLaesstDasPDFUnberuehrt() throws {
        let package = try NotebookPackage.create(title: "Unberuehrt", at: workingDirectory)
        let contentURL = package.url.appending(path: "content.pdf")
        let before = try FileManager.default.attributesOfItem(atPath: contentURL.path)[.systemFileNumber] as? Int

        package.setTitle("Nur der Titel")
        try package.write()

        let after = try FileManager.default.attributesOfItem(atPath: contentURL.path)[.systemFileNumber] as? Int
        XCTAssertNotNil(before)
        XCTAssertEqual(before, after, "content.pdf wurde ohne Seitenaenderung neu geschrieben")
    }

    func testFehlendeSeitenbeschreibungenWerdenRepariert() throws {
        let package = try NotebookPackage.create(title: "Kaputt", at: workingDirectory)
        try package.insertBlankPage()
        try package.insertBlankPage()
        try package.write()

        var broken = package.info
        broken.pages.removeLast(2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(broken).write(to: package.url.appending(path: "info.json"))

        let repaired = try NotebookPackage.read(from: package.url)
        XCTAssertEqual(repaired.pageCount, 3, "Beschreibungen wurden nicht ergaenzt")
        XCTAssertTrue(repaired.loadWarnings.contains { $0.contains("ergaenzt") })
    }

    func testNeueresSchemaWirdAbgelehnt() throws {
        let package = try NotebookPackage.create(title: "Zukunft", at: workingDirectory)
        var future = package.info
        future.schemaVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(future).write(to: package.url.appending(path: "info.json"))

        XCTAssertThrowsError(try NotebookPackage.read(from: package.url)) { error in
            guard case NotebookPackageError.unsupportedSchema = error else {
                return XCTFail("falscher Fehler: \(error)")
            }
        }
    }

    func testFehlendesPaketWirft() {
        XCTAssertThrowsError(
            try NotebookPackage.read(from: workingDirectory.appending(path: "gibtsnicht.bestnote"))
        )
    }

    func testVerwaisteBilderWerdenBeimOeffnenEntfernt() throws {
        let package = try NotebookPackage.create(title: "Muell", at: workingDirectory)
        let asset = package.addAsset(data: TestSupport.makeImagePNG(), fileExtension: "png")
        try package.write()
        XCTAssertNotNil(package.assetData(named: asset))

        let removed = package.pruneUnreferencedAssets()
        XCTAssertEqual(removed, [asset])
        XCTAssertNil(package.assetData(named: asset))
    }
}
