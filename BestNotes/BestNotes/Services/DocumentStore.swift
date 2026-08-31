//
//  DocumentStore.swift
//  BestNotes
//
//  Oeffnet ein Bibliotheksdokument — und zwar immer als Notizbuchpaket.
//

import Foundation
import PDFKit

@MainActor
enum DocumentStore {

    /// - Note: Aeltere Bibliotheken haben importierte PDFs als lose Datei
    ///   abgelegt. Solche Eintraege werden beim ersten Oeffnen in ein Paket
    ///   ueberfuehrt, damit es im Programm nur noch eine Dokumentart gibt.
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
        // Erst nach erfolgreichem Schreiben aufraeumen.
        try? FileManager.default.removeItem(at: legacyPDF)
        return package
    }
}
