//
//  LibraryStore.swift
//  marginalia
//
//  Facade in front of SwiftData. From the outside unchanged compared to
//  step 4: the sidebar still only sees `[LibraryNode]` and the same old
//  operations — only the internals were swapped.
//
//  A fresh tree of value types is built from SwiftData on every change.
//  At library sizes that costs nothing and keeps the views away from the
//  model objects' lifecycles.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {

    private let context: ModelContext
    private(set) var roots: [LibraryNode] = []

    /// Last error while reading or writing — the views display it.
    private(set) var lastError: Error?

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    // MARK: - Loading

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
            documentURL: entry.documentURL,
            lastOpenedAt: entry.lastOpenedAt
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

    // MARK: - Reading (on the cached tree)

    func node(id: UUID) -> LibraryNode? {
        Self.find(id: id, in: roots)
    }

    /// Folder a new item belongs in relative to the selection: into the
    /// selected folder itself, otherwise next to the selected item,
    /// otherwise into the root.
    func insertionTarget(for selection: UUID?) -> UUID? {
        guard let selection, let node = node(id: selection) else { return nil }
        return node.isFolder ? selection : Self.parentID(of: selection, in: roots)
    }

    /// Recently opened documents, newest first.
    func recentlyOpened(limit: Int = 12) -> [LibraryNode] {
        var found: [LibraryNode] = []
        Self.collectDocuments(in: roots, into: &found)
        return found
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    private static func collectDocuments(in nodes: [LibraryNode], into result: inout [LibraryNode]) {
        for node in nodes {
            if node.isFolder {
                collectDocuments(in: node.children ?? [], into: &result)
            } else {
                result.append(node)
            }
        }
    }

    func markOpened(id: UUID, at date: Date = Date()) {
        guard let entry = entry(id: id), entry.kind != .folder else { return }
        entry.lastOpenedAt = date
        commit()
    }

    func path(to id: UUID) -> [LibraryNode] {
        var result: [LibraryNode] = []
        _ = Self.buildPath(to: id, in: roots, into: &result)
        return result
    }

    // MARK: - Creating

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

    /// Creates the database entry *and* the package. If the package fails,
    /// the entry is discarded again — a notebook without a file would be a
    /// dead entry in the sidebar.
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
            try DocumentImporter.importPDF(from: source, as: entry.id, title: name)
        } catch {
            context.delete(entry)
            commit()
            throw error
        }

        commit()
        return entry.id
    }

    // MARK: - Changing

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let entry = entry(id: id) else { return }
        entry.name = trimmed
        entry.modified = Date()
        commit()
    }

    /// Updates the title in `info.json`.
    ///
    /// Only call this when the document is *not* open — otherwise two
    /// `NotebookPackage` instances write to the same file. If it is open,
    /// the session takes care of it on the next save.
    func syncNotebookTitle(id: UUID, to name: String) {
        guard let entry = entry(id: id), entry.kind != .folder,
              let url = entry.documentURL,
              let package = try? NotebookPackage.read(from: url)
        else { return }
        package.setTitle(name)
        try? package.write()
    }

    /// - Returns: the IDs of all removed nodes, including descendants.
    @discardableResult
    func delete(id: UUID) -> Set<UUID> {
        guard let entry = entry(id: id) else { return [] }

        var removed: Set<UUID> = []
        var files: [URL] = []
        Self.collect(entry, ids: &removed, files: &files)

        // Database first, then the files: if a file stays behind, it is
        // garbage — if it disappears too early, the sidebar points at a hole.
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

    // MARK: - Recursive Helpers on the Value-Type Tree

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
