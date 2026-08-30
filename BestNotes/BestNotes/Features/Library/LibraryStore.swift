//
//  LibraryStore.swift
//  BestNotes
//
//  Haelt den Bibliotheksbaum im Speicher. In Schritt 6 wird die Innerei
//  gegen SwiftData getauscht — die oeffentliche Schnittstelle soll dabei
//  gleich bleiben.
//

import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {

    private(set) var roots: [LibraryNode]

    init(roots: [LibraryNode] = LibraryNode.sampleTree) {
        self.roots = roots
    }

    // MARK: - Lesen

    func node(id: UUID) -> LibraryNode? {
        Self.find(id: id, in: roots)
    }

    /// Ordner, in den ein neues Element relativ zur Auswahl gehoert:
    /// in den ausgewaehlten Ordner selbst, sonst neben das ausgewaehlte
    /// Element, sonst in die Wurzel.
    func insertionTarget(for selection: UUID?) -> UUID? {
        guard let selection, let node = node(id: selection) else { return nil }
        return node.isFolder ? selection : Self.parentID(of: selection, in: roots)
    }

    func path(to id: UUID) -> [LibraryNode] {
        var result: [LibraryNode] = []
        _ = Self.buildPath(to: id, in: roots, into: &result)
        return result
    }

    // MARK: - Schreiben

    @discardableResult
    func insert(_ node: LibraryNode, into parentID: UUID?) -> UUID {
        if let parentID {
            Self.mutate(&roots, id: parentID) { parent in
                parent.children = (parent.children ?? []) + [node]
            }
        } else {
            roots.append(node)
        }
        return node.id
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Self.mutate(&roots, id: id) { $0.name = trimmed }
    }

    /// - Returns: die IDs aller entfernten Knoten, inklusive Nachkommen.
    @discardableResult
    func delete(id: UUID) -> Set<UUID> {
        guard let node = node(id: id) else { return [] }
        var removed: Set<UUID> = []
        Self.collectIDs(of: node, into: &removed)
        Self.remove(&roots, id: id)
        return removed
    }

    // MARK: - Rekursive Helfer
    //
    // Der Baum besteht aus Werttypen, also wird beim Aendern die Kette der
    // Elternknoten neu zurueckgeschrieben. Bei Bibliotheksgroessen ist das
    // billiger als eine Referenzstruktur mit manueller Invalidierung.

    private static func find(id: UUID, in nodes: [LibraryNode]) -> LibraryNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let hit = find(id: id, in: children) { return hit }
        }
        return nil
    }

    private static func parentID(of id: UUID, in nodes: [LibraryNode], parent: UUID? = nil) -> UUID? {
        for node in nodes {
            if node.id == id { return parent }
            if let children = node.children,
               let hit = parentID(of: id, in: children, parent: node.id) {
                return hit
            }
        }
        return nil
    }

    @discardableResult
    private static func mutate(
        _ nodes: inout [LibraryNode],
        id: UUID,
        _ body: (inout LibraryNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                body(&nodes[index])
                return true
            }
            if var children = nodes[index].children, mutate(&children, id: id, body) {
                nodes[index].children = children
                return true
            }
        }
        return false
    }

    @discardableResult
    private static func remove(_ nodes: inout [LibraryNode], id: UUID) -> Bool {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes.remove(at: index)
            return true
        }
        for index in nodes.indices {
            if var children = nodes[index].children, remove(&children, id: id) {
                nodes[index].children = children
                return true
            }
        }
        return false
    }

    private static func collectIDs(of node: LibraryNode, into set: inout Set<UUID>) {
        set.insert(node.id)
        node.children?.forEach { collectIDs(of: $0, into: &set) }
    }

    private static func buildPath(
        to id: UUID,
        in nodes: [LibraryNode],
        into result: inout [LibraryNode]
    ) -> Bool {
        for node in nodes {
            result.append(node)
            if node.id == id { return true }
            if let children = node.children, buildPath(to: id, in: children, into: &result) {
                return true
            }
            result.removeLast()
        }
        return false
    }
}

// MARK: - Testdaten
//
// Bewusst ausserhalb der @MainActor-Klasse: als Default-Argument wird der
// Ausdruck nonisolated ausgewertet, was in Swift 6 sonst ein Fehler waere.

extension LibraryNode {
    static let sampleTree: [LibraryNode] = [
        .folder("Studium", [
            .folder("Analysis II", [
                .pdf("Skript Kapitel 1"),
                .pdf("Uebungsblatt 3"),
                .notebook("Vorlesungsmitschrift")
            ]),
            .folder("Datenbanken", [
                .pdf("Folien Normalformen"),
                .notebook("Zusammenfassung")
            ])
        ]),
        .folder("Projekte", [
            .notebook("BestNotes — Ideen"),
            .folder("Archiv", [
                .notebook("Altes Konzept")
            ])
        ]),
        .notebook("Notizen")
    ]
}
