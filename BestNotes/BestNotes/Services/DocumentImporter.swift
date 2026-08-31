//
//  DocumentImporter.swift
//  BestNotes
//

import Foundation
import PDFKit

enum DocumentImportError: LocalizedError {
    case unreadablePDF(URL)
    case copyFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url):
            "„\(url.lastPathComponent)“ konnte nicht als PDF gelesen werden."
        case .copyFailed(let url, _):
            "„\(url.lastPathComponent)“ konnte nicht in die Bibliothek kopiert werden."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadablePDF:
            "Die Datei ist moeglicherweise beschaedigt, passwortgeschuetzt oder kein PDF."
        case .copyFailed:
            "Pruefe, ob genug Speicherplatz frei ist."
        }
    }
}

@MainActor
enum DocumentImporter {

    /// Nimmt eine gewaehlte PDF in die Bibliothek auf — als Notizbuch.
    ///
    /// Die Seiten wandern unveraendert in `content.pdf` des Pakets. Dadurch
    /// gibt es im Programm nur eine Dokumentart: eine importierte PDF laesst
    /// sich sofort annotieren, um leere Seiten ergaenzen und beschreiben.
    ///
    /// Bewusst aufnehmen statt verknuepfen: die Bibliothek besitzt ihre
    /// Dokumente dann selbst. Das erspart security-scoped bookmarks samt
    /// Entitlement, ueberlebt Verschieben und Umbenennen des Originals, und
    /// Annotationen landen in der Kopie statt in der Datei des Nutzers.
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
