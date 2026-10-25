//
//  LibraryStoreTests.swift
//  marginaliaTests
//

import SwiftData
import XCTest
@testable import marginalia

@MainActor
final class LibraryStoreTests: TemporaryDirectoryTestCase {

    private var container: ModelContainer!
    private var store: LibraryStore!
    private var libraryRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Redirect the library into the test folder so nothing ends up in
        // the user's container.
        libraryRoot = workingDirectory.appending(path: "Library")
        setenv("MARGINALIA_LIBRARY_ROOT", libraryRoot.path, 1)

        container = try ModelContainer(
            for: LibraryEntry.self,
            configurations: ModelConfiguration(url: workingDirectory.appending(path: "index.store"))
        )
        store = LibraryStore(context: container.mainContext)
    }

    override func tearDown() async throws {
        unsetenv("MARGINALIA_LIBRARY_ROOT")
        store = nil
        container = nil
        try await super.tearDown()
    }

    func testLibraryRedirectTakesEffect() {
        XCTAssertEqual(NotebookLibraryLocation.libraryRoot.path, libraryRoot.path)
    }

    func testCreatingFolderAndNotebook() throws {
        XCTAssertTrue(store.roots.isEmpty)

        let studies = store.createFolder(name: "Studies", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studies)
        XCTAssertEqual(store.roots.count, 1)
        XCTAssertEqual(store.node(id: studies)?.children?.first?.id, analysis)

        let notebook = try store.createNotebook(name: "Lecture Notes", in: analysis)
        let packageURL = NotebookLibraryLocation.packageURL(for: notebook)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertNil(store.node(id: notebook)?.children, "Notebooks are leaves")
        XCTAssertEqual(store.node(id: notebook)?.documentURL, packageURL)
    }

    /// An imported PDF becomes a notebook — the app only has one kind of
    /// document.
    func testImportCreatesANotebookAndLeavesTheOriginalAlone() throws {
        let source = try TestSupport.makeSamplePDF(pages: 3, at: workingDirectory.appending(path: "source.pdf"))
        let originalSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int

        let entry = try store.importPDF(from: source, name: "Script", in: nil)
        let packageURL = NotebookLibraryLocation.packageURL(for: entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertEqual(store.node(id: entry)?.documentURL, packageURL)

        let package = try NotebookPackage.read(from: packageURL)
        XCTAssertEqual(package.pageCount, 3)
        XCTAssertEqual(package.info.pages.allSatisfy { $0.kind == .imported }, true)
        XCTAssertEqual(package.info.pages.first?.source, "source.pdf")
        XCTAssertEqual(package.title, "Script")

        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int,
            originalSize,
            "The original must not be touched"
        )
    }

    /// Older libraries had imported PDFs as loose files.
    func testLoosePDFIsConvertedOnOpen() throws {
        let entry = LibraryEntry(name: "Old", kind: .pdf)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        store.reload()

        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let legacy = NotebookLibraryLocation.legacyPDFURL(for: entry.id)
        try TestSupport.makeSamplePDF(pages: 2, at: legacy)

        let package = try DocumentStore.openPackage(id: entry.id, title: "Old")
        XCTAssertEqual(package.pageCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "The loose file does not stay behind")
    }

    func testBreadcrumbAndInsertionTarget() throws {
        let studies = store.createFolder(name: "Studies", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studies)
        let notebook = try store.createNotebook(name: "Lecture Notes", in: analysis)

        XCTAssertEqual(store.path(to: notebook).map(\.name), ["Studies", "Analysis II", "Lecture Notes"])
        XCTAssertEqual(store.insertionTarget(for: analysis), analysis, "A folder takes items itself")
        XCTAssertEqual(store.insertionTarget(for: notebook), analysis, "A leaf passes on to its parent folder")
        XCTAssertNil(store.insertionTarget(for: nil))
    }

    func testRenaming() throws {
        let notebook = try store.createNotebook(name: "Old", in: nil)

        store.rename(id: notebook, to: "  New  ")
        XCTAssertEqual(store.node(id: notebook)?.name, "New", "Whitespace is trimmed")

        store.rename(id: notebook, to: "   ")
        XCTAssertEqual(store.node(id: notebook)?.name, "New", "An empty name is rejected")

        store.syncNotebookTitle(id: notebook, to: "New")
        let package = try NotebookPackage.read(from: NotebookLibraryLocation.packageURL(for: notebook))
        XCTAssertEqual(package.title, "New")
    }

    func testStructureSurvivesRelaunch() throws {
        let studies = store.createFolder(name: "Studies", in: nil)
        let notebook = try store.createNotebook(name: "Lecture Notes", in: studies)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        store.markOpened(id: notebook, at: stamp)

        // Close first, then reopen — two containers on the same file are not
        // a relaunch but two writers.
        let storeURL = workingDirectory.appending(path: "index.store")
        store = nil
        container = nil

        let reopenedContainer = try ModelContainer(
            for: LibraryEntry.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let reopened = LibraryStore(context: reopenedContainer.mainContext)

        XCTAssertEqual(reopened.roots.count, 1)
        XCTAssertEqual(reopened.node(id: studies)?.children?.count, 1)
        XCTAssertEqual(reopened.node(id: notebook)?.name, "Lecture Notes")
        XCTAssertEqual(reopened.node(id: notebook)?.lastOpenedAt, stamp)
        XCTAssertEqual(reopened.recentlyOpened().map(\.id), [notebook])
    }

    func testRecentlyOpenedInTheRightOrder() throws {
        let folder = store.createFolder(name: "Studies", in: nil)
        let a = try store.createNotebook(name: "A", in: nil)
        let b = try store.createNotebook(name: "B", in: folder)
        let c = try store.createNotebook(name: "C", in: folder)

        XCTAssertTrue(store.recentlyOpened().isEmpty, "Unopened items do not show up")

        let now = Date()
        store.markOpened(id: a, at: now.addingTimeInterval(-300))
        store.markOpened(id: c, at: now)

        let recents = store.recentlyOpened()
        XCTAssertEqual(recents.map(\.id), [c, a], "Newest first, across folder boundaries too")
        XCTAssertFalse(recents.contains { $0.id == b }, "Never-opened items are missing")
        XCTAssertFalse(recents.contains { $0.isFolder }, "Folders are not documents")

        store.markOpened(id: b, at: now.addingTimeInterval(60))
        XCTAssertEqual(store.recentlyOpened().map(\.id), [b, c, a])
        XCTAssertEqual(store.recentlyOpened(limit: 2).map(\.id), [b, c])
    }

    func testDeletingTakesDescendantsAndFilesAlong() throws {
        let studies = store.createFolder(name: "Studies", in: nil)
        let analysis = store.createFolder(name: "Analysis II", in: studies)
        let notebook = try store.createNotebook(name: "Lecture Notes", in: analysis)
        let source = try TestSupport.makeSamplePDF(at: workingDirectory.appending(path: "source.pdf"))
        let pdf = try store.importPDF(from: source, name: "Script", in: analysis)

        let packageURL = NotebookLibraryLocation.packageURL(for: notebook)
        let pdfURL = NotebookLibraryLocation.packageURL(for: pdf)

        let removed = store.delete(id: studies)
        XCTAssertEqual(removed.count, 4)
        XCTAssertTrue(removed.contains(notebook))
        XCTAssertTrue(store.roots.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "The original stays")
    }
}
