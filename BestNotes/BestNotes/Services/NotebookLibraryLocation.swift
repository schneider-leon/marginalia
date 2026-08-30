//
//  NotebookLibraryLocation.swift
//  BestNotes
//
//  Wo die Notizbuch-Pakete liegen.
//
//  Bewusst im Sandbox-Container (`Documents/Library`) statt an einem frei
//  gewaehlten Ort: damit braucht es keine security-scoped bookmarks, und der
//  Zugriff ueberlebt Neustarts ohne Zutun. Einen frei waehlbaren
//  Bibliotheksordner kann Schritt 9 nachruesten.
//

import Foundation
import UniformTypeIdentifiers

enum NotebookLibraryLocation {

    /// Umlenkbar ueber `BESTNOTES_LIBRARY_ROOT` — fuer Tests und zum
    /// Nachsehen, ohne den Container anzufassen.
    static var libraryRoot: URL {
        if let path = ProcessInfo.processInfo.environment["BESTNOTES_LIBRARY_ROOT"], !path.isEmpty {
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

    /// Paketname aus der Notizbuch-ID statt aus dem Titel: Umbenennen soll
    /// keine Datei verschieben muessen, und zwei gleichnamige Notizbuecher
    /// duerfen nebeneinander existieren. Der Titel steht in `info.json`.
    static func packageURL(for id: UUID, in root: URL? = nil) -> URL {
        (root ?? libraryRoot)
            .appending(path: id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension(UTType.bestNotebookExtension)
    }

    static func pdfURL(for id: UUID, in root: URL? = nil) -> URL {
        (root ?? libraryRoot)
            .appending(path: id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension("pdf")
    }

    /// Datei zu einem Bibliothekseintrag — Ordner haben keine.
    static func documentURL(for id: UUID, kind: LibraryNode.Kind, in root: URL? = nil) -> URL? {
        switch kind {
        case .folder: nil
        case .notebook: packageURL(for: id, in: root)
        case .pdf: pdfURL(for: id, in: root)
        }
    }
}
