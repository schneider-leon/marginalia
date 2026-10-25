//
//  DocumentThumbnails.swift
//  marginalia
//
//  Thumbnails of the first page, for the home screen.
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

    /// Renders synchronously and remembers the result.
    ///
    /// Deliberately not concurrent: the home screen shows a dozen or so
    /// thumbnails, and PDFKit needs a few milliseconds for them. A
    /// concurrency model for this would be more risk than gain — `NSImage`
    /// and `PDFDocument` do not like traveling between threads.
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

    /// After saving, the remembered thumbnail is no longer accurate.
    func invalidate(id: UUID) {
        cache = cache.filter { $0.key.id != id }
    }
}
