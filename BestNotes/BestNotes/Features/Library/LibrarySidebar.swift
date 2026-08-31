//
//  LibrarySidebar.swift
//  BestNotes
//

import SwiftUI

struct LibrarySidebar: View {
    let store: LibraryStore
    @Binding var selection: UUID?

    let onCreateFolder: (UUID?) -> UUID?
    let onCreateNotebook: (UUID?) -> UUID?
    let onImportPDF: (UUID?) -> Void
    let onToggleSidebar: () -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var renaming: RenameRequest?

    var body: some View {
        List(selection: $selection) {
            Section("Bibliothek") {
                OutlineGroup(store.roots, children: \.children) { node in
                    Label(node.name, systemImage: node.symbol)
                        .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.roots.isEmpty {
                // Ohne die Fussleiste ist das „+“ oben nicht mehr in
                // Blickweite — der leere Zustand bietet den Weg selbst an.
                ContentUnavailableView {
                    Label("Bibliothek ist leer", systemImage: "books.vertical")
                } description: {
                    Text("Lege ein Notizbuch an oder importiere eine PDF.")
                } actions: {
                    Button("Notizbuch anlegen") { addNotebook(into: nil) }
                        .buttonStyle(.borderedProminent)
                    Button("PDF importieren …") { onImportPDF(nil) }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids.first)
        }
        // `.primaryAction` landet im Abschnitt der Seitenleiste, `.navigation`
        // dagegen im Dokumentbereich. Den eingebauten Umschalter ersetzen wir,
        // weil er sonst immer aussen sitzt und das „+“ nicht davor passt.
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                addMenu
                sidebarToggle
            }
        }
        .alert("Umbenennen", isPresented: renamingBinding) {
            TextField("Name", text: renameTextBinding)
            Button("Abbrechen", role: .cancel) { renaming = nil }
            Button("Sichern") {
                if let renaming { onRename(renaming.id, renaming.name) }
                renaming = nil
            }
        }
    }

    // MARK: - Kontextmenue

    @ViewBuilder
    private func contextMenu(for id: UUID?) -> some View {
        let target = store.insertionTarget(for: id)

        Button("Neuer Ordner") { addFolder(into: target) }
        Button("Neues Notizbuch") { addNotebook(into: target) }
        Button("PDF importieren …") { onImportPDF(target) }

        if let id, let node = store.node(id: id) {
            Divider()
            Button("Umbenennen …") { renaming = RenameRequest(id: id, name: node.name) }
            Button("Loeschen", role: .destructive) { onDelete(id) }
        }
    }

    // MARK: - Hinzufuegen

    private var addMenu: some View {
        Menu {
            Button("Neuer Ordner") { addFolder(into: store.insertionTarget(for: selection)) }
            Button("Neues Notizbuch") { addNotebook(into: store.insertionTarget(for: selection)) }
            Divider()
            Button("PDF importieren …") { onImportPDF(store.insertionTarget(for: selection)) }
        } label: {
            Label("Hinzufuegen", systemImage: "plus")
        }
        .help("Ordner, Notizbuch oder PDF hinzufuegen")
    }

    private var sidebarToggle: some View {
        Button(action: onToggleSidebar) {
            Label("Bibliothek", systemImage: "sidebar.leading")
        }
        .help("Bibliothek ein- oder ausblenden")
    }

    // MARK: - Aktionen

    private func addFolder(into parent: UUID?) {
        guard let id = onCreateFolder(parent) else { return }
        selection = id
        renaming = RenameRequest(id: id, name: "Neuer Ordner")
    }

    private func addNotebook(into parent: UUID?) {
        guard let id = onCreateNotebook(parent) else { return }
        selection = id
        renaming = RenameRequest(id: id, name: "Neues Notizbuch")
    }

    // MARK: - Umbenennen

    private struct RenameRequest {
        let id: UUID
        var name: String
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    private var renameTextBinding: Binding<String> {
        Binding(
            get: { renaming?.name ?? "" },
            set: { renaming?.name = $0 }
        )
    }
}
