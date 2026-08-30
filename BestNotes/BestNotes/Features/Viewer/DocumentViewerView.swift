//
//  DocumentViewerView.swift
//  BestNotes
//
//  SwiftUI-Chrome um die PDFView: Seitennavigation, Zoom, Anzeigemodus.
//

import SwiftUI

struct DocumentViewerView: View {
    @Bindable var session: DocumentSession

    @State private var pageFieldText = "1"

    var body: some View {
        PDFViewRepresentable(session: session, displayMode: session.displayMode)
            .navigationTitle(session.displayName)
            .navigationSubtitle("\(session.pageCount) Seiten")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    pageNavigation
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    zoomControls
                    displayModePicker
                }
            }
            .onAppear { syncPageField() }
            .onChange(of: session.currentPageIndex) { syncPageField() }
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
}
