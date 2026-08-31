//
//  LibraryEntry.swift
//  BestNotes
//
//  SwiftData-Modell der Bibliothek — der *Index*, nicht der Inhalt.
//
//  Gespeichert wird nur, was die Struktur ausmacht: Name, Art, Ordnung,
//  Elternschaft. Die eigentlichen Dokumente liegen als Dateien daneben und
//  werden ueber die `id` gefunden. Eine kaputte oder migrierte Datenbank
//  kostet damit nie Notizen.
//

import Foundation
import SwiftData

@Model
final class LibraryEntry {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = LibraryNode.Kind.folder.rawValue
    /// Position unter den Geschwistern.
    var sortIndex: Int = 0
    var created: Date = Date()
    var modified: Date = Date()
    /// Wann das Dokument zuletzt geoeffnet wurde — `nil` heisst: noch nie.
    /// Optional, damit SwiftData bestehende Datenbanken ohne Zutun migriert.
    var lastOpenedAt: Date?

    var parent: LibraryEntry?

    @Relationship(deleteRule: .cascade, inverse: \LibraryEntry.parent)
    var children: [LibraryEntry]? = []

    init(id: UUID = UUID(), name: String, kind: LibraryNode.Kind, sortIndex: Int = 0, parent: LibraryEntry? = nil) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.sortIndex = sortIndex
        self.created = Date()
        self.modified = Date()
        self.parent = parent
        self.children = []
    }

    var kind: LibraryNode.Kind {
        get { LibraryNode.Kind(rawValue: kindRaw) ?? .folder }
        set { kindRaw = newValue.rawValue }
    }

    var sortedChildren: [LibraryEntry] {
        (children ?? []).sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
    }

    /// Datei, die zu diesem Eintrag gehoert — `nil` bei Ordnern.
    var documentURL: URL? {
        NotebookLibraryLocation.documentURL(for: id, kind: kind)
    }
}
