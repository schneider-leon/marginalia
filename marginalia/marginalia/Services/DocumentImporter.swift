//
//  DocumentImporter.swift
//  marginalia
//

import Foundation
import PDFKit

enum DocumentImportError: LocalizedError {
    case unreadablePDF(URL)
    case copyFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url):
            "“\(url.lastPathComponent)” could not be read as a PDF."
        case .copyFailed(let url, _):
            "“\(url.lastPathComponent)” could not be copied into the library."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadablePDF:
            "The file may be damaged, password-protected or not a PDF."
        case .copyFailed:
            "Check that there is enough free disk space."
        }
    }
}

@MainActor
enum DocumentImporter {

    /// Adds a chosen PDF to the library — as a notebook.
    ///
    /// The pages move unchanged into the package's `content.pdf`. This way
    /// the app only has one kind of document: an imported PDF can be
    /// annotated right away, extended with blank pages and written on.
    ///
    /// Deliberately imported instead of linked: the library then owns its
    /// documents. That avoids security-scoped bookmarks and the entitlement
    /// they need, survives moving and renaming the original, and annotations
    /// end up in the copy instead of in the user's file.
    @discardableResult
    static func importPDF(from source: URL, as id: UUID, title: String) throws -> URL {
        let access = SecurityScopedAccess(url: source)
        defer { access.release() }

        guard let document = PDFDocument(url: source), document.pageCount > 0 else {
            throw DocumentImportError.unreadablePDF(source)
        }

        do {
            try NotebookLibraryLocation.ensureLibraryRoot()
            let package = try NotebookPackage.create(
                id: id,
                title: title,
                from: document,
                sourceName: source.lastPathComponent,
                at: NotebookLibraryLocation.libraryRoot
            )
            return package.url
        } catch {
            throw DocumentImportError.copyFailed(source, underlying: error)
        }
    }
}
