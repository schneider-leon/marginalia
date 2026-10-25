//
//  LibraryEntry.swift
//  marginalia
//
//  SwiftData model of the library — the *index*, not the content.
//
//  Only what makes up the structure is stored: name, kind, order,
//  parentage. The actual documents live next to it as files and are found
//  via the `id`. A broken or migrated database therefore never costs any
//  notes.
//

import Foundation
import SwiftData

@Model
final class LibraryEntry {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = LibraryNode.Kind.folder.rawValue
    /// Position among the siblings.
    var sortIndex: Int = 0
    var created: Date = Date()
    var modified: Date = Date()
    /// When the document was last opened — `nil` means never.
    /// Optional so SwiftData migrates existing databases without help.
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

    /// File belonging to this entry — `nil` for folders.
    var documentURL: URL? {
        NotebookLibraryLocation.documentURL(for: id, kind: kind)
    }
}
