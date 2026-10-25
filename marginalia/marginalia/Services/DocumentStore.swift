//
//  DocumentStore.swift
//  marginalia
//
//  Opens a library document — always as a notebook package.
//

import Foundation
import PDFKit

@MainActor
enum DocumentStore {

    /// - Note: Older libraries stored imported PDFs as loose files. Such
    ///   entries are converted into a package the first time they are
    ///   opened, so the app only deals with one kind of document.
    static func openPackage(id: UUID, title: String) throws -> NotebookPackage {
        let packageURL = NotebookLibraryLocation.packageURL(for: id)
        if FileManager.default.fileExists(atPath: packageURL.path) {
            return try NotebookPackage.read(from: packageURL)
        }

        let legacy = NotebookLibraryLocation.legacyPDFURL(for: id)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return try migrate(legacyPDF: legacy, id: id, title: title)
        }

        throw NotebookPackageError.missingComponent(packageURL.lastPathComponent)
    }

    private static func migrate(legacyPDF: URL, id: UUID, title: String) throws -> NotebookPackage {
        guard let document = PDFDocument(url: legacyPDF), document.pageCount > 0 else {
            throw NotebookPackageError.unreadablePDF
        }
        let package = try NotebookPackage.create(
            id: id,
            title: title,
            from: document,
            sourceName: legacyPDF.lastPathComponent,
            at: NotebookLibraryLocation.libraryRoot
        )
        // Only clean up after writing succeeded.
        try? FileManager.default.removeItem(at: legacyPDF)
        return package
    }
}
