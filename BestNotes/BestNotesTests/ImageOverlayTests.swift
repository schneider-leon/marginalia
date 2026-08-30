//
//  ImageOverlayTests.swift
//  BestNotesTests
//

import AppKit
import XCTest
@testable import BestNotes

@MainActor
final class ImageOverlayTests: TemporaryDirectoryTestCase {

    private func makeSession(_ title: String = "Bilder") throws -> (NotebookPackage, DocumentSession) {
        let package = try NotebookPackage.create(title: title, at: workingDirectory)
        let session = DocumentSession(package: package, name: title)
        // Ohne Runloop wuerde der UndoManager alle Schritte in eine Gruppe legen.
        session.undoManager.groupsByEvent = false
        return (package, session)
    }

    func testEinfuegenHaeltSeitenverhaeltnisUndBleibtAufDerSeite() throws {
        let (_, session) = try makeSession()
        var id: UUID?
        TestSupport.undoGroup(session.undoManager) {
            id = session.insertImage(
                data: TestSupport.makeImagePNG(size: CGSize(width: 400, height: 300)),
                fileExtension: "png",
                atPageIndex: 0
            )
        }

        XCTAssertNotNil(id)
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).count, 1)
        XCTAssertEqual(session.selectedOverlayID, id)
        XCTAssertTrue(session.hasUnsavedChanges)

        let frame = try XCTUnwrap(session.imageOverlays(atPageIndex: 0).first).frame
        XCTAssertEqual(frame.width / frame.height, 400.0 / 300.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(frame.width, PDFPageFactory.a4.width * 0.5 + 0.5)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, PDFPageFactory.a4.width)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxY, PDFPageFactory.a4.height)
    }

    func testBildIstImExportSichtbar() throws {
        let (package, session) = try makeSession()
        let engine = try XCTUnwrap(session.textEngine)

        let empty = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertEqual(TestSupport.inkPixelCount(in: empty), 0)

        TestSupport.undoGroup(session.undoManager) {
            session.insertImage(data: TestSupport.makeImagePNG(), fileExtension: "png", atPageIndex: 0)
        }
        let withImage = try NotebookRenderer.flattened(package, engine: engine)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: withImage), 1000)
    }

    func testBewegenIstEinUndoSchritt() throws {
        let (_, session) = try makeSession()
        TestSupport.undoGroup(session.undoManager) {
            session.insertImage(data: TestSupport.makeImagePNG(), fileExtension: "png", atPageIndex: 0)
        }
        let overlay = try XCTUnwrap(session.imageOverlays(atPageIndex: 0).first)
        let moved = CGRect(x: 40, y: 600, width: overlay.frame.width, height: overlay.frame.height)

        TestSupport.undoGroup(session.undoManager) {
            session.commitOverlayFrame(id: overlay.id, from: overlay.frame, to: moved, atPageIndex: 0)
        }
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).first?.frame, moved)

        session.undo()
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).first?.frame, overlay.frame)
        session.redo()
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).first?.frame, moved)
    }

    func testBildUeberlebtSichernUndNeuOeffnen() throws {
        let (package, session) = try makeSession()
        TestSupport.undoGroup(session.undoManager) {
            session.insertImage(data: TestSupport.makeImagePNG(), fileExtension: "png", atPageIndex: 0)
        }
        let frame = try XCTUnwrap(session.imageOverlays(atPageIndex: 0).first).frame
        try session.save()

        let assets = try FileManager.default.contentsOfDirectory(
            atPath: package.url.appending(path: "assets").path
        )
        XCTAssertEqual(assets.count, 1)
        XCTAssertTrue(assets[0].hasSuffix(".png"))

        let reopenedPackage = try NotebookPackage.read(from: package.url)
        let reopened = DocumentSession(package: reopenedPackage, name: "Bilder")
        XCTAssertEqual(reopened.imageOverlays(atPageIndex: 0).count, 1)
        XCTAssertEqual(reopened.imageOverlays(atPageIndex: 0).first?.frame, frame)

        guard case .image(let content)? = reopened.imageOverlays(atPageIndex: 0).first?.content else {
            return XCTFail("Bild-Overlay fehlt")
        }
        XCTAssertNotNil(reopened.image(forAsset: content.assetName))

        let flattened = try NotebookRenderer.flattened(reopenedPackage)
        XCTAssertGreaterThan(TestSupport.inkPixelCount(in: flattened), 1000)
    }

    func testLoeschenUndWiderrufen() throws {
        let (_, session) = try makeSession()
        TestSupport.undoGroup(session.undoManager) {
            session.insertImage(data: TestSupport.makeImagePNG(), fileExtension: "png", atPageIndex: 0)
        }
        var second: UUID?
        TestSupport.undoGroup(session.undoManager) {
            second = session.insertImage(
                data: TestSupport.makeImagePNG(size: CGSize(width: 200, height: 200), color: .red),
                fileExtension: "png", atPageIndex: 0
            )
        }
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).last?.id, second, "Neues Bild liegt oben")

        session.selectedOverlayID = second
        TestSupport.undoGroup(session.undoManager) {
            session.removeSelectedOverlay(atPageIndex: 0)
        }
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).count, 1)
        XCTAssertNil(session.selectedOverlayID)

        session.undo()
        XCTAssertEqual(session.imageOverlays(atPageIndex: 0).count, 2)
    }
}
