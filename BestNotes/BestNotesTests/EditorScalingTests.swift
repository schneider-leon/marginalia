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

        XCTAssertEqual(session.currentScale, 1)
        XCTAssertTrue(session.canZoomIn)
        XCTAssertTrue(session.canZoomOut)

        session.zoomIn()
        XCTAssertEqual(session.zoom, 1.25)
        session.zoomOut()
        session.zoomOut()
        XCTAssertEqual(session.zoom, 0.75)

        for _ in 0..<10 { session.zoomOut() }
        XCTAssertEqual(session.zoom, 0.25)
        XCTAssertFalse(session.canZoomOut)
        for _ in 0..<20 { session.zoomIn() }
        XCTAssertEqual(session.zoom, 4)
        XCTAssertFalse(session.canZoomIn)

        session.viewportWidth = 595 + DocumentAppearance.pageGap * 2
        session.fitToWindow()
        XCTAssertEqual(session.zoom, 1, accuracy: 0.001)
    }

    /// Beide Modi teilen sich einen Zoomwert — beim Umschalten darf die
    /// Seite nicht springen.
    func testZoomUeberlebtDenModuswechsel() throws {
        let package = try NotebookPackage.create(title: "Modus", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Modus")

        session.zoomIn()
        session.zoomIn()
        let chosen = session.zoom
        XCTAssertEqual(chosen, 1.5)

        session.notebookMode = .annotate
        XCTAssertEqual(session.zoom, chosen)
        XCTAssertEqual(session.currentScale, chosen)

        session.zoomOut()
        XCTAssertEqual(session.zoom, 1.25)

        session.notebookMode = .write
        XCTAssertEqual(session.zoom, 1.25, "Der Zoom gehoert dem Dokument, nicht dem Modus")
    }

    /// Die PDFView kann selbst zoomen (Trackpad); der Wert muss im
    /// gemeinsamen Zoom landen.
    func testZoomAusDerPDFViewWirdUebernommen() throws {
        let package = try NotebookPackage.create(title: "Trackpad", at: workingDirectory)
        let session = DocumentSession(package: package, name: "Trackpad")

        session.reportScale(2.0)
        XCTAssertEqual(session.zoom, 2.0)

        session.reportScale(99)
        XCTAssertEqual(session.zoom, 4, "Ausserhalb der Stufen wird geklemmt")
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
