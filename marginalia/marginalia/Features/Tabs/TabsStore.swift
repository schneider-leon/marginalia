//
//  TabsStore.swift
//  marginalia
//
//  Manages the open documents. A tab carries the ID of its library node —
//  that keeps sidebar selection, renaming and deleting in sync without an
//  additional mapping table.
//

import Foundation
import Observation

/// `@MainActor` because `hasUnsavedChanges` reaches into the session —
/// without the annotation that would be an error under Swift 6.
@MainActor
struct DocumentTab: Identifiable {
    let id: UUID
    var title: String
    var kind: LibraryNode.Kind

    /// Only for PDFs with a file behind them. Placeholder nodes and
    /// notebooks (until step 6) have none.
    var session: DocumentSession?

    var symbol: String { kind.symbol }
    var hasUnsavedChanges: Bool { session?.hasUnsavedChanges ?? false }
}

@MainActor
@Observable
final class TabsStore {

    private(set) var tabs: [DocumentTab] = []

    /// `nil` means the home screen is active. It is always there and cannot
    /// be closed, so it needs no entry of its own in `tabs` — the absence of
    /// a document *is* the state.
    private(set) var activeID: UUID?

    var activeTab: DocumentTab? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    var isEmpty: Bool { tabs.isEmpty }

    func tab(id: UUID) -> DocumentTab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Opening & Activating

    /// Opens the node in a tab, or activates the existing one.
    /// Folders get no tab.
    func open(_ node: LibraryNode) throws {
        guard node.kind != .folder else { return }

        if tabs.contains(where: { $0.id == node.id }) {
            activeID = node.id
            return
        }

        // Every document is opened as a notebook package — an imported PDF
        // too. There is no second way.
        var session: DocumentSession?
        if node.documentURL != nil {
            let package = try DocumentStore.openPackage(id: node.id, title: node.name)
            session = DocumentSession(package: package, name: node.name)
        }

        tabs.append(DocumentTab(id: node.id, title: node.name, kind: node.kind, session: session))
        activeID = node.id
    }

    var isShowingHome: Bool { activeID == nil }

    func activateHome() {
        activeID = nil
    }

    func activate(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    func activate(index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeID = tabs[index].id
    }

    func activateNext() { shiftActive(by: 1) }
    func activatePrevious() { shiftActive(by: -1) }

    private func shiftActive(by offset: Int) {
        guard !tabs.isEmpty,
              let activeID,
              let index = tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        // Modulo with correction so -1 at the left edge wraps to the end.
        let next = ((index + offset) % tabs.count + tabs.count) % tabs.count
        self.activeID = tabs[next].id
    }

    // MARK: - Closing

    func close(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].session?.close()
        tabs.remove(at: index)

        guard activeID == id else { return }
        // Move up: first the tab at the same position, otherwise the last one.
        activeID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
    }

    func close(ids: Set<UUID>) {
        for id in ids { close(id: id) }
    }

    func closeOthers(than id: UUID) {
        close(ids: Set(tabs.map(\.id).filter { $0 != id }))
    }

    func closeAll() {
        close(ids: Set(tabs.map(\.id)))
    }

    /// Saves all open documents — on quit and before risky steps.
    /// - Returns: Titles of the documents that failed to save.
    @discardableResult
    func saveAll() -> [String] {
        tabs.compactMap { tab in
            guard let session = tab.session else { return nil }
            return session.saveQuietly() ? nil : tab.title
        }
    }

    // MARK: - Mirroring the Library

    func rename(id: UUID, to title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
        tabs[index].session?.displayName = title
    }

    /// Whether this node is currently open — decides who updates the title
    /// in the package.
    func isOpen(_ id: UUID) -> Bool {
        tabs.contains { $0.id == id }
    }
}
