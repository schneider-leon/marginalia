//
//  LibraryStoreTests.swift
//  BestNotesTests
//

import SwiftData
import XCTest
@testable import BestNotes

@MainActor
final class LibraryStoreTests: TemporaryDirectoryTestCase {

    private var container: ModelContainer!
    private var store: LibraryStore!
    private var libraryRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Die Bibliothek in den Testordner umlenken, damit nichts im
        // Container des Nutzers landet.
        libraryRoot = workingDirectory.appending(path: "Library")
        setenv("BESTNOTES_LIBRARY_ROOT", libraryRoot.path, 1)

        container = try ModelContainer(
            for: LibraryEntry.self,
            configurations: ModelConfiguration(url: workingDirectory.appending(path: "index.store"))
        )
        store = LibraryStore(context: container.mainContext)
    }

    override func tearDown() async throws {
        unsetenv("BESTNOTES_LIBRARY_ROOT")
        store = nil
        container = nil
        try await super.tearDown()
    }

    func testUmlenkungDerBibliothekGreift() {
        XCTAssertEqual(NotebookLibraryLocation.libraryRoot.path, libraryRoot.path)
    }

    func testOrdnerUndNotizbuchAnlegen() throws {
        XCTAssertTrue(store.roots.isEmpty)

        let studium = store.createFolder(name: "Studium", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studium)
        XCTAssertEqual(store.roots.count, 1)
        XCTAssertEqual(store.node(id: studium)?.children?.first?.id, analysis)

        let notebook = try store.createNotebook(name: "Mitschrift", in: analysis)
        let packageURL = NotebookLibraryLocation.packageURL(for: notebook)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertNil(store.node(id: notebook)?.children, "Notizbuecher sind Blaetter")
        XCTAssertEqual(store.node(id: notebook)?.documentURL, packageURL)
    }

    /// Eine importierte PDF wird zum Notizbuch — es gibt im Programm nur
    /// eine Dokumentart.
    func testImportLegtEinNotizbuchAnUndLaesstDasOriginalInRuhe() throws {
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "quelle.pdf"))
        let originalSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int

        let entry = try store.importPDF(from: source, name: "Skript", in: nil)
        let packageURL = NotebookLibraryLocation.packageURL(for: entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertEqual(store.node(id: entry)?.documentURL, packageURL)

        let package = try NotebookPackage.read(from: packageURL)
        XCTAssertEqual(package.pageCount, 3)
        XCTAssertEqual(package.info.pages.allSatisfy { $0.kind == .imported }, true)
        XCTAssertEqual(package.info.pages.first?.source, "quelle.pdf")
        XCTAssertEqual(package.title, "Skript")

        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int,
            originalSize,
            "Das Original darf nicht angefasst werden"
        )
    }

    /// Aeltere Bibliotheken hatten importierte PDFs als lose Datei.
    func testLoseLiegendePDFWirdBeimOeffnenUeberfuehrt() throws {
        let entry = LibraryEntry(name: "Alt", kind: .pdf)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        store.reload()

        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let legacy = NotebookLibraryLocation.legacyPDFURL(for: entry.id)
        try TestSupport.makeSamplePDF(pages: 2, at: legacy)

        let package = try DocumentStore.openPackage(id: entry.id, title: "Alt")
        XCTAssertEqual(package.pageCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "Die lose Datei bleibt nicht liegen")
    }

    func testBreadcrumbUndEinfuegeziel() throws {
        let studium = store.createFolder(name: "Studium", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studium)
        let notebook = try store.createNotebook(name: "Mitschrift", in: analysis)

        XCTAssertEqual(store.path(to: notebook).map(\.name), ["Studium", "Analysis II", "Mitschrift"])
        XCTAssertEqual(store.insertionTarget(for: analysis), analysis, "Ordner nimmt selbst auf")
        XCTAssertEqual(store.insertionTarget(for: notebook), analysis, "Blatt reicht an den Elternordner")
        XCTAssertNil(store.insertionTarget(for: nil))
    }

    func testUmbenennen() throws {
        let notebook = try store.createNotebook(name: "Alt", in: nil)

        store.rename(id: notebook, to: "  Neu  ")
        XCTAssertEqual(store.node(id: notebook)?.name, "Neu", "Leerraum wird abgeschnitten")

        store.rename(id: notebook, to: "   ")
        XCTAssertEqual(store.node(id: notebook)?.name, "Neu", "Leerer Name wird abgewiesen")

        store.syncNotebookTitle(id: notebook, to: "Neu")
        let package = try NotebookPackage.read(from: NotebookLibraryLocation.packageURL(for: notebook))
        XCTAssertEqual(package.title, "Neu")
    }

    func testStrukturUeberlebtDenNeustart() throws {
        let studium = store.createFolder(name: "Studium", in: nil)
        let notebook = try store.createNotebook(name: "Mitschrift", in: studium)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        store.markOpened(id: notebook, at: stamp)

        // Erst schliessen, dann neu oeffnen — zwei Container auf derselben
        // Datei sind kein Neustart, sondern zwei Schreiber.
        let storeURL = workingDirectory.appending(path: "index.store")
        store = nil
        container = nil

        let reopenedContainer = try ModelContainer(
            for: LibraryEntry.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let reopened = LibraryStore(context: reopenedContainer.mainContext)

        XCTAssertEqual(reopened.roots.count, 1)
        XCTAssertEqual(reopened.node(id: studium)?.children?.count, 1)
        XCTAssertEqual(reopened.node(id: notebook)?.name, "Mitschrift")
        XCTAssertEqual(reopened.node(id: notebook)?.lastOpenedAt, stamp)
        XCTAssertEqual(reopened.recentlyOpened().map(\.id), [notebook])
    }

    func testZuletztGeoeffneteInDerRichtigenReihenfolge() throws {
        let ordner = store.createFolder(name: "Studium", in: nil)
        let a = try store.createNotebook(name: "A", in: nil)
        let b = try store.createNotebook(name: "B", in: ordner)
        let c = try store.createNotebook(name: "C", in: ordner)

        XCTAssertTrue(store.recentlyOpened().isEmpty, "Ungeoeffnetes taucht nicht auf")

        let now = Date()
        store.markOpened(id: a, at: now.addingTimeInterval(-300))
        store.markOpened(id: c, at: now)

        let recents = store.recentlyOpened()
        XCTAssertEqual(recents.map(\.id), [c, a], "Neueste zuerst, auch ueber Ordnergrenzen hinweg")
        XCTAssertFalse(recents.contains { $0.id == b }, "Nie geoeffnetes fehlt")
        XCTAssertFalse(recents.contains { $0.isFolder }, "Ordner sind keine Dokumente")

        store.markOpened(id: b, at: now.addingTimeInterval(60))
        XCTAssertEqual(store.recentlyOpened().map(\.id), [b, c, a])
        XCTAssertEqual(store.recentlyOpened(limit: 2).map(\.id), [b, c])
    }

    func testLoeschenNimmtNachkommenUndDateienMit() throws {
        let studium = store.createFolder(name: "Studium", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studium)
        let notebook = try store.createNotebook(name: "Mitschrift", in: analysis)
        let source = try TestSupport.makeSamplePDF(at: workingDirectory.appending(path: "quelle.pdf"))
        let pdf = try store.importPDF(from: source, name: "Skript", in: analysis)

        let packageURL = NotebookLibraryLocation.packageURL(for: notebook)
        let pdfURL = NotebookLibraryLocation.packageURL(for: pdf)

        let removed = store.delete(id: studium)
        XCTAssertEqual(removed.count, 4)
        XCTAssertTrue(removed.contains(notebook))
        XCTAssertTrue(store.roots.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Das Original bleibt")
    }
}
