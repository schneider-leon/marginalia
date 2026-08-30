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

    static var libraryRoot: URL {
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
}
