//
//  LibraryNode.swift
//  BestNotes
//
//  Baummodell der Bibliothek. Bewusst ein Werttyp: die Sidebar soll in
//  Schritt 6 auf SwiftData umgestellt werden koennen, ohne dass die Views
//  etwas davon mitbekommen — sie kennen nur `LibraryNode` und den Store.
//

import Foundation

struct LibraryNode: Identifiable, Hashable {

    enum Kind: String, Hashable {
        case folder
        case notebook
        case pdf

        var symbol: String {
            switch self {
            case .folder: "folder"
            case .notebook: "book.closed"
            case .pdf: "doc.richtext"
            }
        }

        var label: String {
            switch self {
            case .folder: "Ordner"
            case .notebook: "Notizbuch"
            case .pdf: "PDF"
            }
        }
    }

    let id: UUID
    var name: String
    var kind: Kind

    /// `nil` bei Blaettern — `OutlineGroup` blendet den Aufklapppfeil daran aus.
    var children: [LibraryNode]?

    /// Datei in der Bibliothek — `nil` bei Ordnern.
    var documentURL: URL?

    var lastOpenedAt: Date?

    var isFolder: Bool { kind == .folder }
    var symbol: String { kind.symbol }

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        children: [LibraryNode]? = nil,
        documentURL: URL? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.children = kind == .folder ? (children ?? []) : children
        self.documentURL = documentURL
        self.lastOpenedAt = lastOpenedAt
    }

    static func folder(_ name: String, _ children: [LibraryNode] = []) -> LibraryNode {
        LibraryNode(name: name, kind: .folder, children: children)
    }

    static func notebook(_ name: String) -> LibraryNode {
        LibraryNode(name: name, kind: .notebook)
    }

    static func pdf(_ name: String, url: URL? = nil) -> LibraryNode {
        LibraryNode(name: name, kind: .pdf, documentURL: url)
    }

    static func notebook(_ name: String, url: URL?) -> LibraryNode {
        LibraryNode(name: name, kind: .notebook, documentURL: url)
    }
}
