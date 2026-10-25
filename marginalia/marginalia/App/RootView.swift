//
//  RootView.swift
//  marginalia
//
//  Root layout: library on the left, tab bar and active document on the
//  right.
//
//  Rule for the detail area: it *always* shows the active tab. A folder in
//  the sidebar gets no tab and leaves the display unchanged — otherwise
//  every selection would have to decide whether it overrides the tab stack.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    let library: LibraryStore
    var startupWarning: String? = nil

    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var tabs = TabsStore()
    @State private var selection: UUID?

    @State private var isImporterPresented = false
    @State private var importTarget: UUID?
    @State private var failure: ViewerFailure?
    @State private var pendingClose: PendingClose?

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            LibrarySidebar(
                store: library,
                selection: $selection,
                onCreateFolder: createFolder(in:),
                onCreateNotebook: createNotebook(in:),
                onImportPDF: presentImporter(into:),
                isSidebarVisible: sidebarVisibility != .detailOnly,
                onRename: rename(id:to:),
                onDelete: delete(id:)
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            detail
                // Always visible, on the home screen too: otherwise the house
                // tab would be a one-way switch that disappears with its own
                // click.
                .safeAreaInset(edge: .top, spacing: 0) {
                    DocumentTabBar(store: tabs, onRequestClose: requestClose(id:))
                }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .focusedSceneValue(\.openDocumentAction, presentImporterAtSelection)
        .focusedSceneValue(\.toggleSidebarAction, toggleSidebar)
        .focusedSceneValue(\.closeTabAction, closeActiveTab)
        .focusedSceneValue(\.tabsStore, tabs)
        // macOS draws the separator under the title bar based on the
        // content's scroll state — that looked different from document to
        // document. It stays off; the tab bar sets itself apart through its
        // background, not through lines.
        .configureWindow { $0.titlebarSeparatorStyle = .none }
        .task { showStartupWarningIfNeeded() }
        // Safety net under autosave: on quit and when the app is sent to the
        // background, everything is written out once more.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            tabs.saveAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            tabs.saveAll()
        }
        .onChange(of: selection) { openSelectedNode() }
        .onChange(of: tabs.activeID) { syncSelectionToActiveTab() }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            pendingClose.map { "“\($0.title)” could not be saved." } ?? "",
            isPresented: pendingCloseBinding,
            titleVisibility: .visible
        ) {
            Button("Try Again") { resolvePendingClose(saving: true) }
            Button("Close Anyway", role: .destructive) { resolvePendingClose(saving: false) }
            Button("Keep Open", role: .cancel) { pendingClose = nil }
        } message: {
            Text("The changes could not be saved. They will be lost if you close the tab.")
        }
    }

    // MARK: - Detail Area

    @ViewBuilder
    private var detail: some View {
        if let tab = tabs.activeTab {
            content(for: tab)
                .id(tab.id)
        } else {
            HomeView(
                library: library,
                onOpen: { selection = $0 },
                onImport: presentImporterAtSelection
            )
        }
    }

    @ViewBuilder
    private func content(for tab: DocumentTab) -> some View {
        if let session = tab.session {
            // The background belongs here, not in the two modes: that way it
            // cannot change when switching.
            Group {
                if session.notebookMode == .write {
                    NotebookEditorView(session: session)
                } else {
                    DocumentViewerView(session: session)
                }
            }
            .background(Color.documentBackground)
        } else {
            ContentUnavailableView {
                Label(tab.title, systemImage: tab.symbol)
            } description: {
                Text(placeholderMessage(for: tab.kind))
            }
            .navigationTitle(tab.title)
        }
    }

    private func placeholderMessage(for kind: LibraryNode.Kind) -> String {
        switch kind {
        case .notebook, .pdf: "The document could not be opened."
        case .folder: ""
        }
    }

    // MARK: - Selection <-> Tabs

    private func openSelectedNode() {
        guard let id = selection, let node = library.node(id: id), node.kind != .folder else { return }
        do {
            try tabs.open(node)
            library.markOpened(id: id)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }

    /// The other direction: switching tabs highlights the node in the
    /// sidebar. The equality check keeps both directions from rocking each
    /// other.
    private func syncSelectionToActiveTab() {
        guard let activeID = tabs.activeID else {
            // Home screen: nothing in the library is currently open.
            selection = nil
            return
        }
        guard selection != activeID else { return }
        selection = activeID
    }

    /// For the menu command with a keyboard shortcut. macOS provides the
    /// button in the window toolbar itself.
    private func toggleSidebar() {
        withAnimation(.easeOut(duration: 0.2)) {
            sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    // MARK: - Import

    private func presentImporterAtSelection() {
        presentImporter(into: library.insertionTarget(for: selection))
    }

    private func presentImporter(into parent: UUID?) {
        importTarget = parent
        isImporterPresented = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        let target = importTarget
        importTarget = nil

        switch result {
        case .success(let urls):
            var lastID: UUID?
            for url in urls {
                do {
                    lastID = try library.importPDF(
                        from: url,
                        name: url.deletingPathExtension().lastPathComponent,
                        in: target
                    )
                } catch {
                    failure = ViewerFailure(error: error)
                }
            }
            if let lastID { selection = lastID }
        case .failure(let error):
            failure = ViewerFailure(error: error)
        }
    }

    // MARK: - Creating

    private func createFolder(in parent: UUID?) -> UUID? {
        library.createFolder(name: "New Folder", in: parent)
    }

    private func createNotebook(in parent: UUID?) -> UUID? {
        do {
            return try library.createNotebook(name: "New Notebook", in: parent)
        } catch {
            failure = ViewerFailure(error: error)
            return nil
        }
    }

    private func showStartupWarningIfNeeded() {
        guard let startupWarning, failure == nil else { return }
        failure = ViewerFailure(message: startupWarning, suggestion: nil)
    }

    // MARK: - Changing the Library

    private func rename(id: UUID, to name: String) {
        library.rename(id: id, to: name)
        guard let updated = library.node(id: id) else { return }

        if tabs.isOpen(id) {
            // The open session is the only writer to the package; it updates
            // the title on the next save.
            tabs.rename(id: id, to: updated.name)
        } else if updated.kind != .folder {
            library.syncNotebookTitle(id: id, to: updated.name)
        }
    }

    private func delete(id: UUID) {
        let removed = library.delete(id: id)
        tabs.close(ids: removed)
        if let selection, removed.contains(selection) {
            self.selection = tabs.activeID
        }
    }

    // MARK: - Closing Tabs

    private struct PendingClose: Identifiable {
        let id: UUID
        let title: String
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { pendingClose != nil },
            set: { if !$0 { pendingClose = nil } }
        )
    }

    private func closeActiveTab() {
        guard let activeID = tabs.activeID else { return }
        requestClose(id: activeID)
    }

    /// Closing saves. We only ask if that fails — otherwise the prompt would
    /// just be in the way with autosave active.
    private func requestClose(id: UUID) {
        guard let tab = tabs.tab(id: id) else { return }
        guard tab.hasUnsavedChanges, let session = tab.session else {
            tabs.close(id: id)
            return
        }
        if session.saveQuietly() {
            tabs.close(id: id)
        } else {
            pendingClose = PendingClose(id: id, title: tab.title)
        }
    }

    private func resolvePendingClose(saving: Bool) {
        guard let pending = pendingClose else { return }
        pendingClose = nil

        if saving, let session = tabs.tab(id: pending.id)?.session {
            guard session.saveQuietly() else {
                return  // Keep the tab open so nothing is lost.
            }
        }
        tabs.close(id: pending.id)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: LibraryEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootView(library: LibraryStore(context: container.mainContext))
}
