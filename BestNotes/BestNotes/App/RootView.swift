//
//  RootView.swift
//  BestNotes
//
//  Wurzel-Layout: Bibliothek links, Tab-Leiste und aktives Dokument rechts.
//
//  Regel fuer den Detailbereich: er zeigt *immer* den aktiven Tab. Ein Ordner
//  in der Sidebar bekommt keinen Tab und laesst die Anzeige unveraendert —
//  sonst muesste jede Auswahl entscheiden, ob sie den Tab-Stapel ueberschreibt.
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
                onToggleSidebar: toggleSidebar,
                onRename: rename(id:to:),
                onDelete: delete(id:)
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !tabs.isEmpty {
                        DocumentTabBar(store: tabs, onRequestClose: requestClose(id:))
                    }
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
        .task { showStartupWarningIfNeeded() }
        // Netz unter der Autosicherung: beim Beenden und beim Wegklicken der
        // App wird noch einmal alles weggeschrieben.
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
            pendingClose.map { "„\($0.title)“ konnte nicht gesichert werden." } ?? "",
            isPresented: pendingCloseBinding,
            titleVisibility: .visible
        ) {
            Button("Erneut versuchen") { resolvePendingClose(saving: true) }
            Button("Trotzdem schliessen", role: .destructive) { resolvePendingClose(saving: false) }
            Button("Offen lassen", role: .cancel) { pendingClose = nil }
        } message: {
            Text("Die Aenderungen konnten nicht gesichert werden. Beim Schliessen gehen sie verloren.")
        }
    }

    // MARK: - Detailbereich

    @ViewBuilder
    private var detail: some View {
        if let tab = tabs.activeTab {
            content(for: tab)
                .id(tab.id)
        } else {
            ContentUnavailableView {
                Label("Kein Dokument geoeffnet", systemImage: "doc.richtext")
            } description: {
                Text("Waehle links ein Dokument, oder importiere eine PDF.")
            } actions: {
                Button("PDF importieren …", action: presentImporterAtSelection)
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("BestNotes")
        }
    }

    @ViewBuilder
    private func content(for tab: DocumentTab) -> some View {
        if let session = tab.session {
            if session.notebook != nil, session.notebookMode == .write {
                NotebookEditorView(session: session)
                    .focusedSceneValue(\.documentSession, session)
            } else {
                DocumentViewerView(session: session)
            }
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
        case .notebook: "Das Notizbuchpaket konnte nicht geoeffnet werden."
        case .pdf: "Die Datei zu diesem Eintrag fehlt in der Bibliothek."
        case .folder: ""
        }
    }

    // MARK: - Auswahl <-> Tabs

    private func openSelectedNode() {
        guard let id = selection, let node = library.node(id: id), node.kind != .folder else { return }
        do {
            try tabs.open(node)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }

    /// Gegenrichtung: ein Tab-Wechsel hebt den Knoten in der Sidebar hervor.
    /// Die Gleichheitspruefung verhindert, dass sich beide Richtungen
    /// gegenseitig aufschaukeln.
    private func syncSelectionToActiveTab() {
        guard let activeID = tabs.activeID, selection != activeID else { return }
        selection = activeID
    }

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

    // MARK: - Anlegen

    private func createFolder(in parent: UUID?) -> UUID? {
        library.createFolder(name: "Neuer Ordner", in: parent)
    }

    private func createNotebook(in parent: UUID?) -> UUID? {
        do {
            return try library.createNotebook(name: "Neues Notizbuch", in: parent)
        } catch {
            failure = ViewerFailure(error: error)
            return nil
        }
    }

    private func showStartupWarningIfNeeded() {
        guard let startupWarning, failure == nil else { return }
        failure = ViewerFailure(message: startupWarning, suggestion: nil)
    }

    // MARK: - Bibliothek aendern

    private func rename(id: UUID, to name: String) {
        library.rename(id: id, to: name)
        guard let updated = library.node(id: id) else { return }

        if tabs.isOpen(id) {
            // Die offene Session ist die einzige Schreiberin auf dem Paket;
            // sie zieht den Titel beim naechsten Sichern nach.
            tabs.rename(id: id, to: updated.name)
        } else if updated.kind == .notebook {
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

    // MARK: - Tabs schliessen

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

    /// Beim Schliessen wird gesichert. Nachgefragt wird nur, wenn das
    /// scheitert — sonst waere die Rueckfrage bei aktiver Autosicherung nur
    /// noch im Weg.
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
                return  // Tab offen lassen, damit nichts verloren geht.
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
