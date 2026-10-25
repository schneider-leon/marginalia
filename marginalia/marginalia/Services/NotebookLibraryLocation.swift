//
//  NotebookLibraryLocation.swift
//  marginalia
//
//  Where the notebook packages live.
//
//  Deliberately inside the sandbox container (`Documents/Library`) instead
//  of a freely chosen location: that way no security-scoped bookmarks are
//  needed, and access survives relaunches without any extra work. A freely
//  selectable library folder can be added in step 9.
//

import Foundation
import UniformTypeIdentifiers

enum NotebookLibraryLocation {

    /// Can be redirected via `MARGINALIA_LIBRARY_ROOT` — for tests and for
    /// looking around without touching the container.
    static var libraryRoot: URL {
        if let path = ProcessInfo.processInfo.environment["MARGINALIA_LIBRARY_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "Library", directoryHint: .isDirectory)
    }

    @discardableResult
    static func ensureLibraryRoot() throws -> URL {
        let root = libraryRoot
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Package name from the notebook ID instead of the title: renaming
    /// should not have to move any file, and two notebooks with the same
    /// name may exist side by side. The title is stored in `info.json`.
    static func packageURL(for id: UUID, in root: URL? = nil) -> URL {
        (root ?? libraryRoot)
            .appending(path: id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension(UTType.marginaliaNotebookExtension)
    }

    /// Only for migrating older libraries in which imported PDFs were
    /// stored as loose files.
    static func legacyPDFURL(for id: UUID, in root: URL? = nil) -> URL {
        (root ?? libraryRoot)
            .appending(path: id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension("pdf")
    }

    /// File for a library entry — folders have none.
    ///
    /// Notebooks and imported PDFs are both stored as packages: `kind` now
    /// only determines the icon in the sidebar, not the format.
    static func documentURL(for id: UUID, kind: LibraryNode.Kind, in root: URL? = nil) -> URL? {
        kind == .folder ? nil : packageURL(for: id, in: root)
    }
}
