//
//  DocumentThumbnails.swift
//  BestNotes
//
//  Miniaturen der ersten Seite, fuer die Startseite.
//

import AppKit
import Foundation
import PDFKit

@MainActor
final class DocumentThumbnails {
    static let shared = DocumentThumbnails()

    private struct Key: Hashable {
        let id: UUID
        let width: Int
    }

    private var cache: [Key: NSImage] = [:]

    private init() {}

    /// Rendert synchron und merkt sich das Ergebnis.
    ///
    /// Bewusst nicht nebenlaeufig: auf der Startseite stehen ein gutes
    /// Dutzend Miniaturen, und PDFKit braucht dafuer wenige Millisekunden.
    /// Ein Nebenlaeufigkeitsmodell dafuer waere mehr Risiko als Gewinn —
    /// `NSImage` und `PDFDocument` reisen nicht gern zwischen Threads.
    func thumbnail(for id: UUID, width: CGFloat) -> NSImage? {
        let key = Key(id: id, width: Int(width.rounded()))
        if let cached = cache[key] { return cached }

        let packageURL = NotebookLibraryLocation.packageURL(for: id)
        let contentURL = packageURL.appending(path: NotebookPackage.Component.content)
        guard let document = PDFDocument(url: contentURL),
              let page = document.page(at: 0)
        else { return nil }

        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        let image = page.thumbnail(of: size, for: .cropBox)
        cache[key] = image
        return image
    }

    /// Nach dem Sichern stimmt die gemerkte Miniatur nicht mehr.
    func invalidate(id: UUID) {
        cache = cache.filter { $0.key.id != id }
    }
}
