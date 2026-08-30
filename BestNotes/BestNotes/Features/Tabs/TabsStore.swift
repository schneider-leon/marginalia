//
//  TabsStore.swift
//  BestNotes
//
//  Verwaltet die offenen Dokumente. Ein Tab traegt die ID seines
//  Bibliotheks-Knotens — damit bleiben Sidebar-Auswahl, Umbenennen und
//  Loeschen ohne zusaetzliche Zuordnungstabelle synchron.
//

import Foundation
import Observation

/// `@MainActor`, weil `hasUnsavedChanges` in die Session hineingreift —
/// ohne die Annotation waere das unter Swift 6 ein Fehler.
@MainActor
struct DocumentTab: Identifiable {
    let id: UUID
    var title: String
    var kind: LibraryNode.Kind

    /// Nur bei PDFs mit hinterlegter Datei. Platzhalter-Knoten und
    /// Notizbuecher (bis Schritt 6) haben keine.
    var session: DocumentSession?

    var symbol: String { kind.symbol }
    var hasUnsavedChanges: Bool { session?.hasUnsavedChanges ?? false }
}

@MainActor
@Observable
final class TabsStore {

    private(set) var tabs: [DocumentTab] = []
    private(set) var activeID: UUID?

    var activeTab: DocumentTab? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    var isEmpty: Bool { tabs.isEmpty }

    func tab(id: UUID) -> DocumentTab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Oeffnen & Aktivieren

    /// Oeffnet den Knoten in einem Tab, oder aktiviert den vorhandenen.
    /// Ordner bekommen keinen Tab.
    func open(_ node: LibraryNode) throws {
        guard node.kind != .folder else { return }

        if tabs.contains(where: { $0.id == node.id }) {
            activeID = node.id
            return
        }

        var session: DocumentSession?
        if let url = node.documentURL {
            switch node.kind {
            case .pdf:
                session = try DocumentSession(pdfAt: url, name: node.name)
            case .notebook:
                session = DocumentSession(package: try NotebookPackage.read(from: url), name: node.name)
            case .folder:
                break
            }
        }

        tabs.append(DocumentTab(id: node.id, title: node.name, kind: node.kind, session: session))
        activeID = node.id
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
        // Modulo mit Korrektur, damit -1 am linken Rand hinten landet.
        let next = ((index + offset) % tabs.count + tabs.count) % tabs.count
        self.activeID = tabs[next].id
    }

    // MARK: - Schliessen

    func close(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].session?.close()
        tabs.remove(at: index)

        guard activeID == id else { return }
        // Nachruecken: erst der Tab an gleicher Position, sonst der letzte.
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

    // MARK: - Bibliothek gespiegelt

    func rename(id: UUID, to title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
        tabs[index].session?.displayName = title
    }

    /// Ob dieser Knoten gerade offen ist — entscheidet, wer den Titel im
    /// Paket nachzieht.
    func isOpen(_ id: UUID) -> Bool {
        tabs.contains { $0.id == id }
    }
}
