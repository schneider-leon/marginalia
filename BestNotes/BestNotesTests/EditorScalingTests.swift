//
//  EditorScalingTests.swift
//  BestNotesTests
//

import AppKit
import XCTest
@testable import BestNotes

@MainActor
final class EditorScalingTests: TemporaryDirectoryTestCase {

    /// Der Zoom im Schreibmodus skaliert ueber `bounds`, nicht ueber ein
    /// nachtraeglich vergroessertes Bild — sonst waere der Text unscharf.
    func testSeiteBehaeltIhrKoordinatensystemBeimZoomen() {
        let view = NotebookPageBackgroundView()
        view.pageSize = PDFPageFactory.a4
        view.frame = CGRect(origin: .zero, size: PDFPageFactory.a4)
        XCTAssertEqual(view.bounds.size, PDFPageFactory.a4)

        view.frame = CGRect(origin: .zero, size: CGSize(width: 595 * 2, height: 842 * 2))
        XCTAssertEqual(view.bounds.size, PDFPageFactory.a4, "Beim Zoomen darf sich bounds nicht mitaendern")

        view.frame = CGRect(origin: .zero, size: CGSize(width: 595 * 0.5, height: 842 * 0.5))
        XCTAssertEqual(view.bounds.size, PDFPageFactory.a4)
    }

    func testZoomstufenUndAnpassenAnDieFensterbreite() throws {
        let package = try NotebookPackage.create(title: "Zoom", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Zoom")

        XCTAssertTrue(session.isTextEditing)
        XCTAssertEqual(session.currentScale, 1)
        XCTAssertTrue(session.canZoomIn)
        XCTAssertTrue(session.canZoomOut)

        session.zoomIn()
        XCTAssertEqual(session.editorZoom, 1.25)
        session.zoomOut()
        session.zoomOut()
        XCTAssertEqual(session.editorZoom, 0.75)

        // Bis an den Anschlag und nicht darueber hinaus
        for _ in 0..<10 { session.zoomOut() }
        XCTAssertEqual(session.editorZoom, 0.5)
        XCTAssertFalse(session.canZoomOut)
        for _ in 0..<20 { session.zoomIn() }
        XCTAssertEqual(session.editorZoom, 3)
        XCTAssertFalse(session.canZoomIn)

        session.editorViewportWidth = 595 + 64
        session.fitToWindow()
        XCTAssertEqual(session.editorZoom, 1, accuracy: 0.001)
    }

    func testZoomBefehleGehenImAnnotationsmodusAnDiePDFView() throws {
        let package = try NotebookPackage.create(title: "Modus", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Modus")

        session.notebookMode = .annotate
        XCTAssertFalse(session.isTextEditing)

        let before = session.editorZoom
        session.zoomIn()
        XCTAssertEqual(session.editorZoom, before, "Im Annotationsmodus darf der Editorzoom sich nicht aendern")
        XCTAssertEqual(session.currentScale, session.scaleFactor)
    }

    func testSeiteZeichnetInhaltAuchVergroessert() throws {
        let package = try NotebookPackage.create(title: "Gezeichnet", at: workingDirectory)
        package.setRuling(.lines)

        let view = NotebookPageBackgroundView()
        view.pageSize = PDFPageFactory.a4
        view.ruling = .lines
        view.insets = .standard
        view.lineHeight = 16
        view.frame = CGRect(origin: .zero, size: CGSize(width: 595 * 2, height: 842 * 2))

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        var ink = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if color.brightnessComponent < 0.97 || color.saturationComponent > 0.05 { ink += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 1000, "Auch vergroessert muessen die Linien gezeichnet werden")
    }
}
