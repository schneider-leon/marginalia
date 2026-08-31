//
//  DocumentViewerView.swift
//  BestNotes
//
//  SwiftUI-Chrome um die PDFView. Die Fensterleiste kommt aus
//  `DocumentToolbarContent` und ist mit der des Schreibmodus identisch.
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
            DocumentToolbarContent(
                session: session,
                currentIndex: session.currentPageIndex,
                pageCount: session.pageCount,
                goPrevious: session.goToPreviousPage,
                goNext: session.goToNextPage,
                goTo: { session.go(toPageIndex: $0) },
                export: exportCopy
            )
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

    // MARK: - Export

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
