//
//  LibrarySidebar.swift
//  marginalia
//

import SwiftUI

struct LibrarySidebar: View {
    let store: LibraryStore
    @Binding var selection: UUID?

    let onCreateFolder: (UUID?) -> UUID?
    let onCreateNotebook: (UUID?) -> UUID?
    let onImportPDF: (UUID?) -> Void
    /// Whether the library is currently visible. The "+" belongs to it and
    /// disappears with it.
    let isSidebarVisible: Bool
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var renaming: RenameRequest?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                OutlineGroup(store.roots, children: \.children) { node in
                    Label(node.name, systemImage: node.symbol)
                        .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.roots.isEmpty {
                // Without the footer the "+" at the top is out of sight —
                // the empty state offers the way itself.
                ContentUnavailableView {
                    Label("Library Is Empty", systemImage: "books.vertical")
                } description: {
                    Text("Create a notebook or import a PDF.")
                } actions: {
                    Button("Create Notebook") { addNotebook(into: nil) }
                        .buttonStyle(.borderedProminent)
                    Button("Import PDF…") { onImportPDF(nil) }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids.first)
        }
        // The built-in toggle stays: AppKit right-aligns it in the sidebar's
        // section of the toolbar and gives it the pill look. A custom button
        // gets neither — it ended up left of the window buttons and without
        // a background.
        //
        // `.primaryAction` lands in the sidebar's section (`.navigation`, by
        // contrast, in the document area); the spacer pushes the "+" from
        // the left up to the toggle.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSidebarVisible {
                    Spacer()
                    addMenu
                }
            }
        }
        .alert("Rename", isPresented: renamingBinding) {
            TextField("Name", text: renameTextBinding)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { onRename(renaming.id, renaming.name) }
                renaming = nil
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for id: UUID?) -> some View {
        let target = store.insertionTarget(for: id)

        Button("New Folder") { addFolder(into: target) }
        Button("New Notebook") { addNotebook(into: target) }
        Button("Import PDF…") { onImportPDF(target) }

        if let id, let node = store.node(id: id) {
            Divider()
            Button("Rename…") { renaming = RenameRequest(id: id, name: node.name) }
            Button("Delete", role: .destructive) { onDelete(id) }
        }
    }

    // MARK: - Adding

    private var addMenu: some View {
        Menu {
            Button("New Folder") { addFolder(into: store.insertionTarget(for: selection)) }
            Button("New Notebook") { addNotebook(into: store.insertionTarget(for: selection)) }
            Divider()
            Button("Import PDF…") { onImportPDF(store.insertionTarget(for: selection)) }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .help("Add a folder, notebook or PDF")
    }


    // MARK: - Actions

    private func addFolder(into parent: UUID?) {
        guard let id = onCreateFolder(parent) else { return }
        selection = id
        renaming = RenameRequest(id: id, name: "New Folder")
    }

    private func addNotebook(into parent: UUID?) {
        guard let id = onCreateNotebook(parent) else { return }
        selection = id
        renaming = RenameRequest(id: id, name: "New Notebook")
    }

    // MARK: - Renaming

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
