//
//  LibraryNode.swift
//  marginalia
//
//  Tree model of the library. Deliberately a value type: the sidebar
//  should be able to switch to SwiftData in step 6 without the views
//  noticing — they only know `LibraryNode` and the store.
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
            case .folder: "Folder"
            case .notebook: "Notebook"
            case .pdf: "PDF"
            }
        }
    }

    let id: UUID
    var name: String
    var kind: Kind

    /// `nil` for leaves — `OutlineGroup` hides the disclosure arrow for them.
    var children: [LibraryNode]?

    /// File in the library — `nil` for folders.
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
