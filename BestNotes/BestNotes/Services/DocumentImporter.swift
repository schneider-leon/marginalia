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

    /// Kopiert eine gewaehlte PDF in die Bibliothek.
    ///
    /// Bewusst kopieren statt verknuepfen: die Bibliothek besitzt ihre
    /// Dokumente dann selbst. Das erspart security-scoped bookmarks samt
    /// Entitlement, ueberlebt Verschieben und Umbenennen des Originals, und
    /// Annotationen landen in der Kopie statt in der Datei des Nutzers.
    /// Preis: doppelter Speicherplatz. Ein „verknuepfen statt kopieren“
    /// liesse sich spaeter mit Bookmarks nachruesten.
    @discardableResult
    static func importPDF(from source: URL, as id: UUID) throws -> URL {
        let access = SecurityScopedAccess(url: source)
        defer { access.release() }

        guard PDFDocument(url: source) != nil else {
            throw DocumentImportError.unreadablePDF(source)
        }

        try NotebookLibraryLocation.ensureLibraryRoot()
        let destination = NotebookLibraryLocation.pdfURL(for: id)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw DocumentImportError.copyFailed(source, underlying: error)
        }
        return destination
    }
}
