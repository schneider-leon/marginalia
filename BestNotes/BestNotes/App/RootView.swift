//
//  RootView.swift
//  BestNotes
//
//  Wurzel-Layout: Bibliothek links, Dokument rechts. Die Sitzungen werden
//  hier pro Bibliotheks-Knoten zwischengespeichert — daraus wird in Schritt 5
//  die Tab-Verwaltung.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var library = LibraryStore()
    @State private var selection: UUID?

    /// Geoeffnete Dokumente, damit Zoom- und Scrollposition beim Wechsel
    /// zwischen Knoten erhalten bleiben.
    @State private var sessions: [UUID: DocumentSession] = [:]

    @State private var isImporterPresented = false
    @State private var importTarget: UUID?
    @State private var failure: ViewerFailure?

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            LibrarySidebar(
                store: library,
                selection: $selection,
                onImportPDF: presentImporter(into:),
                onDelete: delete(id:)
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            detail
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .focusedSceneValue(\.openDocumentAction, presentImporterAtSelection)
        .onChange(of: selection) { ensureSessionForSelection() }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Detailbereich

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let node = library.node(id: id) {
            switch node.kind {
            case .pdf:
                pdfDetail(for: node)
            case .notebook:
                placeholder(
                    symbol: node.symbol,
                    title: node.name,
                    message: "Notizbuecher bekommen ihr eigenes Format in Schritt 6."
                )
            case .folder:
                folderDetail(for: node)
            }
        } else {
            placeholder(
                symbol: "sidebar.leading",
                title: "Nichts ausgewaehlt",
                message: "Waehle links ein Dokument, oder importiere eine PDF."
            )
        }
    }

    @ViewBuilder
    private func pdfDetail(for node: LibraryNode) -> some View {
        if let session = sessions[node.id] {
            DocumentViewerView(session: session)
                .id(session.id)
        } else {
            placeholder(
                symbol: node.symbol,
                title: node.name,
                message: "Testeintrag ohne hinterlegte Datei — importiere eine echte PDF, um sie zu oeffnen."
            )
        }
    }

    private func folderDetail(for node: LibraryNode) -> some View {
        let children = node.children ?? []
        let breadcrumb = library.path(to: node.id).map(\.name).joined(separator: " › ")
        return placeholder(
            symbol: children.isEmpty ? "folder" : "folder.fill",
            title: breadcrumb,
            message: children.isEmpty
                ? "Dieser Ordner ist leer."
                : "\(children.count) Eintraege"
        )
    }

    private func placeholder(symbol: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .navigationTitle(title)
    }

    // MARK: - Sitzungen

    private func ensureSessionForSelection() {
        guard let id = selection,
              let node = library.node(id: id),
              node.kind == .pdf,
              let url = node.fileURL,
              sessions[id] == nil
        else { return }

        do {
            sessions[id] = try DocumentSession(url: url)
        } catch {
            failure = ViewerFailure(error: error)
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
        switch result {
        case .success(let urls):
            var lastID: UUID?
            for url in urls {
                let node = LibraryNode.pdf(url.deletingPathExtension().lastPathComponent, url: url)
                library.insert(node, into: importTarget)
                lastID = node.id
            }
            importTarget = nil
            if let lastID {
                selection = lastID
                ensureSessionForSelection()
            }
        case .failure(let error):
            importTarget = nil
            failure = ViewerFailure(error: error)
        }
    }

    // MARK: - Loeschen

    private func delete(id: UUID) {
        let removed = library.delete(id: id)
        for removedID in removed {
            sessions.removeValue(forKey: removedID)?.close()
        }
        if let selection, removed.contains(selection) {
            self.selection = nil
        }
    }
}

#Preview {
    RootView()
}
