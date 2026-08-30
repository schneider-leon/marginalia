//
//  RootView.swift
//  BestNotes
//
//  Wurzel-Layout. Haelt derzeit genau ein offenes Dokument; ab Schritt 5
//  uebernimmt das eine Tab-Verwaltung.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var session: DocumentSession?
    @State private var isImporterPresented = false
    @State private var openFailure: OpenFailure?

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            ContentUnavailableView {
                Label("Bibliothek", systemImage: "sidebar.leading")
            } description: {
                Text("Ordner & Notizbuecher — Schritt 4")
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            detail
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .focusedSceneValue(\.openDocumentAction, presentImporter)
        .focusedSceneValue(\.documentSession, session)
        .alert(item: $openFailure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session {
            DocumentViewerView(session: session)
                .id(session.id)
        } else {
            ContentUnavailableView {
                Label("Kein Dokument geoeffnet", systemImage: "doc.richtext")
            } description: {
                Text("Oeffne eine PDF-Datei, um sie anzusehen.")
            } actions: {
                Button("PDF oeffnen …", action: presentImporter)
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("BestNotes")
        }
    }

    // MARK: - Oeffnen

    private func presentImporter() {
        isImporterPresented = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            open(url)
        case .failure(let error):
            openFailure = OpenFailure(error: error)
        }
    }

    private func open(_ url: URL) {
        do {
            let newSession = try DocumentSession(url: url)
            session?.close()
            session = newSession
        } catch {
            openFailure = OpenFailure(error: error)
        }
    }
}

// MARK: - Fehleranzeige

private struct OpenFailure: Identifiable {
    let id = UUID()
    let message: String
    let suggestion: String?

    init(error: Error) {
        let localized = error as? LocalizedError
        message = localized?.errorDescription ?? error.localizedDescription
        suggestion = localized?.recoverySuggestion
    }
}

#Preview {
    RootView()
}
