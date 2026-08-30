//
//  DocumentViewerView.swift
//  BestNotes
//
//  SwiftUI-Chrome um die PDFView: Werkzeuge, Seitennavigation, Zoom, Export.
//

import SwiftUI

struct DocumentViewerView: View {
    @Bindable var session: DocumentSession

    @State private var pageFieldText = "1"
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
                pageNavigation
            }
            ToolbarItemGroup(placement: .primaryAction) {
                zoomControls
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
        .onAppear { syncPageField() }
        .onChange(of: session.currentPageIndex) { syncPageField() }
    }

    private var subtitle: String {
        let pages = "\(session.pageCount) Seiten"
        return session.hasUnsavedChanges ? "\(pages) — bearbeitet" : pages
    }

    // MARK: - Seitennavigation

    private var pageNavigation: some View {
        HStack(spacing: 4) {
            Button {
                session.goToPreviousPage()
            } label: {
                Label("Vorherige Seite", systemImage: "chevron.up")
            }
            .disabled(!session.canGoToPreviousPage)

            Button {
                session.goToNextPage()
            } label: {
                Label("Naechste Seite", systemImage: "chevron.down")
            }
            .disabled(!session.canGoToNextPage)

            TextField("Seite", text: $pageFieldText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .onSubmit(jumpToTypedPage)

            Text("von \(session.pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func syncPageField() {
        pageFieldText = String(session.currentPageIndex + 1)
    }

    private func jumpToTypedPage() {
        if let number = Int(pageFieldText.trimmingCharacters(in: .whitespaces)),
           (1...max(session.pageCount, 1)).contains(number) {
            session.go(toPageIndex: number - 1)
        }
        syncPageField()
    }

    // MARK: - Zoom

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                session.zoomOut()
            } label: {
                Label("Verkleinern", systemImage: "minus.magnifyingglass")
            }
            .disabled(session.scaleFactor <= session.minScaleFactor)

            Button(action: session.fitToWindow) {
                Text(zoomLabel)
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help("Auf Fensterbreite anpassen")

            Button {
                session.zoomIn()
            } label: {
                Label("Vergroessern", systemImage: "plus.magnifyingglass")
            }
            .disabled(session.scaleFactor >= session.maxScaleFactor)
        }
    }

    private var zoomLabel: String {
        "\(Int((session.scaleFactor * 100).rounded()))\u{00A0}%"
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
