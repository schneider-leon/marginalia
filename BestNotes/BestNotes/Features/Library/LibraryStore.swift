//
//  LibraryStore.swift
//  BestNotes
//
//  Fassade vor SwiftData. Nach aussen unveraendert gegenueber Schritt 4:
//  die Sidebar sieht weiterhin nur `[LibraryNode]` und die immer gleichen
//  Operationen — getauscht wurde nur die Innerei.
//
//  Aus SwiftData wird bei jeder Aenderung ein frischer Baum aus Werttypen
//  gebaut. Das kostet bei Bibliotheksgroessen nichts und haelt die Views von
//  den Lebenszyklen der Modellobjekte fern.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {

    private let context: ModelContext
    private(set) var roots: [LibraryNode] = []

    /// Letzter Fehler beim Lesen oder Schreiben — die Views zeigen ihn an.
    private(set) var lastError: Error?

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    // MARK: - Laden

    func reload() {
        do {
            let all = try context.fetch(FetchDescriptor<LibraryEntry>())
            let rootEntries = all
                .filter { $0.parent == nil }
                .sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
            roots = rootEntries.map(Self.node(from:))
        } catch {
            lastError = error
            roots = []
        }
    }

    private static func node(from entry: LibraryEntry) -> LibraryNode {
        LibraryNode(
            id: entry.id,
            name: entry.name,
            kind: entry.kind,
            children: entry.kind == .folder ? entry.sortedChildren.map(node(from:)) : nil,
            documentURL: entry.documentURL
        )
    }

    private func entry(id: UUID) -> LibraryEntry? {
        let descriptor = FetchDescriptor<LibraryEntry>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func nextSortIndex(in parent: LibraryEntry?) -> Int {
        let siblings: [LibraryEntry]
        if let parent {
            siblings = parent.children ?? []
        } else {
            siblings = ((try? context.fetch(FetchDescriptor<LibraryEntry>())) ?? [])
                .filter { $0.parent == nil }
        }
        return (siblings.map(\.sortIndex).max() ?? -1) + 1
    }

    private func commit() {
        do {
            try context.save()
        } catch {
            lastError = error
        }
        reload()
    }

    // MARK: - Lesen (auf dem zwischengespeicherten Baum)

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

    // MARK: - Anlegen

    @discardableResult
    func createFolder(name: String, in parentID: UUID?) -> UUID {
        let parent = parentID.flatMap(entry(id:))
        let entry = LibraryEntry(
            name: name,
            kind: .folder,
            sortIndex: nextSortIndex(in: parent),
            parent: parent
        )
        context.insert(entry)
        commit()
        return entry.id
    }

    /// Legt Datenbankeintrag *und* Paket an. Schlaegt das Paket fehl, wird der
    /// Eintrag wieder verworfen — ein Notizbuch ohne Datei waere eine Leiche
    /// in der Sidebar.
    @discardableResult
    func createNotebook(name: String, in parentID: UUID?) throws -> UUID {
        let parent = parentID.flatMap(entry(id:))
        let entry = LibraryEntry(
            name: name,
            kind: .notebook,
            sortIndex: nextSortIndex(in: parent),
            parent: parent
        )
        context.insert(entry)

        do {
            try NotebookLibraryLocation.ensureLibraryRoot()
            _ = try NotebookPackage.create(
                id: entry.id,
                title: name,
                at: NotebookLibraryLocation.libraryRoot
            )
        } catch {
            context.delete(entry)
            commit()
            throw error
        }

        commit()
        return entry.id
    }

    @discardableResult
    func importPDF(from source: URL, name: String, in parentID: UUID?) throws -> UUID {
        let parent = parentID.flatMap(entry(id:))
        let entry = LibraryEntry(
            name: name,
            kind: .pdf,
            sortIndex: nextSortIndex(in: parent),
            parent: parent
        )
        context.insert(entry)

        do {
            try DocumentImporter.importPDF(from: source, as: entry.id)
        } catch {
            context.delete(entry)
            commit()
            throw error
        }

        commit()
        return entry.id
    }

    // MARK: - Aendern

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let entry = entry(id: id) else { return }
        entry.name = trimmed
        entry.modified = Date()
        commit()
    }

    /// Zieht den Titel in `info.json` nach.
    ///
    /// Nur aufrufen, wenn das Notizbuch *nicht* offen ist — sonst schreiben
    /// zwei `NotebookPackage`-Instanzen auf dieselbe Datei. Ist es offen,
    /// erledigt das die Session beim naechsten Sichern.
    func syncNotebookTitle(id: UUID, to name: String) {
        guard let entry = entry(id: id), entry.kind == .notebook,
              let url = entry.documentURL,
              let package = try? NotebookPackage.read(from: url)
        else { return }
        package.setTitle(name)
        try? package.write()
    }

    /// - Returns: die IDs aller entfernten Knoten, inklusive Nachkommen.
    @discardableResult
    func delete(id: UUID) -> Set<UUID> {
        guard let entry = entry(id: id) else { return [] }

        var removed: Set<UUID> = []
        var files: [URL] = []
        Self.collect(entry, ids: &removed, files: &files)

        // Erst die Datenbank, dann die Dateien: bleibt eine Datei liegen,
        // ist das Muell — verschwindet sie zu frueh, zeigt die Sidebar auf
        // ein Loch.
        context.delete(entry)
        commit()

        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
        return removed
    }

    private static func collect(_ entry: LibraryEntry, ids: inout Set<UUID>, files: inout [URL]) {
        ids.insert(entry.id)
        if let url = entry.documentURL { files.append(url) }
        for child in entry.children ?? [] {
            collect(child, ids: &ids, files: &files)
        }
    }

    // MARK: - Rekursive Helfer auf dem Werttyp-Baum

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
