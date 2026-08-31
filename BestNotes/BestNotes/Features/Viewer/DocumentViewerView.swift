//
//  DocumentViewerView.swift
//  BestNotes
//
//  SwiftUI-Chrome um die PDFView: Werkzeuge, Seitennavigation, Zoom, Export.
//

import SwiftUI

struct DocumentViewerView: View {
    @Bindable var session: DocumentSession

    @State private var failure: ViewerFailure?

    var body: some View {
        PDFViewRepresentable(
            session: session,
            displayMode: session.displayMode,
            activeTool: session.activeTool,
            style: session.style
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            AnnotationToolbar(session: session)
        }
        .navigationTitle(session.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                PageNavigationControls(
                    currentIndex: session.currentPageIndex,
                    pageCount: session.pageCount,
                    goPrevious: session.goToPreviousPage,
                    goNext: session.goToNextPage,
                    goTo: { session.go(toPageIndex: $0) }
                )
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ZoomControls(
                    scale: session.currentScale,
                    canZoomIn: session.canZoomIn,
                    canZoomOut: session.canZoomOut,
                    zoomIn: session.zoomIn,
                    zoomOut: session.zoomOut,
                    fit: session.fitToWindow,
                    fitHelp: "Auf Fensterbreite anpassen"
                )
                displayModePicker
                exportButton
            }
        }
        .sheet(item: $session.pendingComment) { _ in
            CommentSheet(
                onCancel: { session.pendingComment = nil },
                onCommit: { session.commitPendingComment(text: $0) }
            )
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
        .focusedSceneValue(\.documentSession, session)
        .focusedSceneValue(\.saveDocumentAction, saveInPlace)
        .focusedSceneValue(\.exportDocumentAction, exportCopy)
        .sessionAlerts(session)
    }

    private var subtitle: String {
        let pages = "\(session.pageCount) Seiten"
        return session.hasUnsavedChanges ? "\(pages) — bearbeitet" : pages
    }

    // MARK: - Anzeigemodus

    private var displayModePicker: some View {
        Picker("Anzeige", selection: $session.displayMode) {
            ForEach(PageDisplayMode.allCases) { mode in
                Label(mode.label, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Export

    private var exportButton: some View {
        Button {
            exportCopy()
        } label: {
            Label("Exportieren", systemImage: "square.and.arrow.up")
        }
        .help("Annotierte PDF an einen anderen Ort schreiben")
    }

    private func exportCopy() {
        do {
            try session.exportCopy()
        } catch {
            failure = ViewerFailure(error: error)
        }
    }

    private func saveInPlace() {
        guard session.hasUnsavedChanges else { return }
        do {
            try session.save()
        } catch {
            failure = ViewerFailure(error: error)
        }
    }
}

struct ViewerFailure: Identifiable {
    let id = UUID()
    let message: String
    let suggestion: String?

    init(message: String, suggestion: String?) {
        self.message = message
        self.suggestion = suggestion
    }

    init(error: Error) {
        let localized = error as? LocalizedError
        message = localized?.errorDescription ?? error.localizedDescription
        suggestion = localized?.recoverySuggestion
    }
}
