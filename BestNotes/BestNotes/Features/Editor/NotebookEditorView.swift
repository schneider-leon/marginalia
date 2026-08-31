//
//  NotebookEditorView.swift
//  BestNotes
//
//  Der Schreibmodus eines Notizbuchs: Seiten untereinander, durchlaufender
//  Text, der von Seite zu Seite fliesst.
//
//  Die Fensterleiste ist dieselbe wie in der PDF-Ansicht — Seitennavigation
//  links, Zoom und Export rechts. Nur die schmale Leiste darunter traegt das,
//  was zum jeweiligen Modus gehoert.
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct NotebookEditorView: View {
    @Bindable var session: DocumentSession

    @State private var failure: ViewerFailure?
    @State private var showsLoadWarnings = false
    @State private var visiblePageID: UUID?

    private let pageGap: CGFloat = 24

    var body: some View {
        ScrollView {
            // Bewusst kein LazyVStack: die Textansichten teilen sich einen
            // Layout-Manager, und ein Container darf nur eine Ansicht haben.
            // Beim Wegwerfen und Neuaufbauen beim Scrollen waere das fragil.
            VStack(spacing: pageGap) {
                ForEach(Array(session.pageDescriptors.enumerated()), id: \.element.id) { index, descriptor in
                    pageView(index: index, descriptor: descriptor)
                }
            }
            .frame(maxWidth: .infinity)
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, pageGap, for: .scrollContent)
        .scrollPosition(id: $visiblePageID)
        .background(Color(nsColor: .underPageBackgroundColor))
        .background { viewportWidthReader }
        .safeAreaInset(edge: .top, spacing: 0) { modeToolbar }
        .navigationTitle(session.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                PageNavigationControls(
                    currentIndex: currentPageIndex,
                    pageCount: session.pageDescriptors.count,
                    goPrevious: { goToPage(currentPageIndex - 1) },
                    goNext: { goToPage(currentPageIndex + 1) },
                    goTo: goToPage
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
                rulingPicker
                exportButton
            }
        }
        .sessionAlerts(session)
        .focusedSceneValue(\.saveDocumentAction, saveInPlace)
        .focusedSceneValue(\.exportDocumentAction, exportCopy)
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var subtitle: String {
        let pages = "\(session.pageDescriptors.count) Seiten"
        return session.hasUnsavedChanges ? "\(pages) — bearbeitet" : pages
    }

    // MARK: - Seitenlage

    /// Die oberste sichtbare Seite; bevor gescrollt wurde, die zuletzt
    /// angeklickte.
    private var currentPageIndex: Int {
        if let visiblePageID,
           let index = session.pageDescriptors.firstIndex(where: { $0.id == visiblePageID }) {
            return index
        }
        return min(session.activePageIndex, max(session.pageDescriptors.count - 1, 0))
    }

    private func goToPage(_ index: Int) {
        guard session.pageDescriptors.indices.contains(index) else { return }
        session.activePageIndex = index
        withAnimation(.easeOut(duration: 0.2)) {
            visiblePageID = session.pageDescriptors[index].id
        }
    }

    private var viewportWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { session.editorViewportWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in
                    session.editorViewportWidth = width
                }
        }
    }

    // MARK: - Seiten

    @ViewBuilder
    private func pageView(index: Int, descriptor: PageDescriptor) -> some View {
        let size = session.document.page(at: index)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
        let zoom = session.editorZoom
        let containerIndex = session.notebook?.writablePageIndices.firstIndex(of: index)

        NotebookPageView(
            session: session,
            pageIndex: index,
            containerIndex: containerIndex,
            pageSize: size,
            ruling: session.ruling,
            insets: session.notebook?.info.textInsets ?? .standard,
            overlayRevision: session.overlayRevision,
            selectedOverlayID: session.selectedOverlayID
        )
        .frame(width: size.width * zoom, height: size.height * zoom)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .overlay(alignment: .bottomTrailing) {
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
                .offset(y: 20)
        }
        .contextMenu {
            Button("Bild einfuegen …") { insertImage(onPage: index) }
            Divider()
            Button("Leere Seite danach einfuegen") { session.insertBlankPage(after: index) }
            Button("Seite loeschen", role: .destructive) { session.removePage(at: index) }
                .disabled(session.pageDescriptors.count < 2)
        }
    }

    // MARK: - Modusleiste
    //
    // Das Gegenstueck zur `AnnotationToolbar`: gleiche Hoehe, gleicher
    // Aufbau, nur andere Werkzeuge.

    private var modeToolbar: some View {
        HStack(spacing: 12) {
            Picker("Modus", selection: $session.notebookMode) {
                ForEach(NotebookMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Divider().frame(height: 18)

            Button {
                session.insertBlankPage()
            } label: {
                Label("Seite anhaengen", systemImage: "plus.rectangle.portrait")
            }
            .help("Leere Seite am Ende anhaengen")

            Button {
                insertImage(onPage: currentPageIndex)
            } label: {
                Label("Bild einfuegen", systemImage: "photo.badge.plus")
            }
            .help("Bild auf der aktuellen Seite einfuegen — oder eine Datei auf die Seite ziehen")

            Divider().frame(height: 18)

            Button(action: session.toggleBold) {
                Label("Fett", systemImage: "bold")
            }
            Button(action: session.toggleItalic) {
                Label("Kursiv", systemImage: "italic")
            }

            Menu {
                ForEach([9, 10, 11, 12, 13, 14, 18, 24, 36], id: \.self) { size in
                    Button("\(size) pt") { session.setFontSize(CGFloat(size)) }
                }
            } label: {
                Label("Schriftgroesse", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            if !session.loadWarnings.isEmpty {
                Button {
                    showsLoadWarnings = true
                } label: {
                    Label("Hinweise", systemImage: "exclamationmark.triangle.fill")
                }
                .help("Beim Oeffnen wurde etwas zurechtgerueckt")
                .popover(isPresented: $showsLoadWarnings, arrowEdge: .bottom) {
                    loadWarningsPopover
                }
            }

            if session.hasUnsavedChanges {
                Text("Nicht gesichert")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var loadWarningsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Beim Oeffnen zurechtgerueckt")
                .font(.headline)
            ForEach(session.loadWarnings, id: \.self) { warning in
                Label(warning, systemImage: "wrench.adjustable")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Verstanden") {
                    showsLoadWarnings = false
                    session.dismissLoadWarnings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Gegenstueck zum Anzeigemodus-Picker der PDF-Ansicht: gleiche Stelle,
    /// gleiche Form, nur betrifft es hier die Seitendarstellung.
    private var rulingPicker: some View {
        Picker("Linien", selection: rulingBinding) {
            ForEach(PageRuling.allCases) { ruling in
                Label(ruling.label, systemImage: ruling.symbol).tag(ruling)
            }
        }
        .pickerStyle(.menu)
    }

    private var rulingBinding: Binding<PageRuling> {
        Binding(
            get: { session.ruling },
            set: { session.setRuling($0) }
        )
    }

    // MARK: - Aktionen

    private var exportButton: some View {
        Button(action: exportCopy) {
            Label("Exportieren", systemImage: "square.and.arrow.up")
        }
        .help("Als PDF exportieren — getippter Text wird eingebrannt")
    }

    private func saveInPlace() {
        guard session.hasUnsavedChanges else { return }
        do { try session.save() } catch { failure = ViewerFailure(error: error) }
    }

    private func exportCopy() {
        do { try session.exportCopy() } catch { failure = ViewerFailure(error: error) }
    }

    private func insertImage(onPage index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.title = "Bild einfuegen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let page = min(max(index, 0), max(session.pageDescriptors.count - 1, 0))
            try session.insertImage(from: url, atPageIndex: page)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }
}
