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

    private let pageGap = DocumentAppearance.pageGap

    var body: some View {
        ScrollView(needsHorizontalScrolling ? [.vertical, .horizontal] : .vertical) {
            // Bewusst kein LazyVStack: die Textansichten teilen sich einen
            // Layout-Manager, und ein Container darf nur eine Ansicht haben.
            // Beim Wegwerfen und Neuaufbauen beim Scrollen waere das fragil.
            VStack(spacing: pageGap) {
                ForEach(pageRows, id: \.id) { row in
                    HStack(alignment: .top, spacing: pageGap) {
                        ForEach(row.indices, id: \.self) { index in
                            pageView(index: index)
                        }
                    }
                }
            }
            // Ohne waagerechtes Scrollen die Breite fuellen, damit die
            // Seiten mittig stehen; sonst nur so breit wie noetig.
            .frame(maxWidth: needsHorizontalScrolling ? nil : .infinity)
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, pageGap, for: .scrollContent)
        .scrollPosition(id: $visiblePageID)
        .onChange(of: visiblePageID) { _, id in followScrollPosition(id) }
        .task { restoreScrollPosition() }
        .background { viewportWidthReader }
        .safeAreaInset(edge: .top, spacing: 0) { modeToolbar }
        .navigationTitle(session.displayName)
        .navigationSubtitle(session.subtitle)
        .toolbar {
            DocumentToolbarContent(
                session: session,
                currentIndex: currentPageIndex,
                pageCount: session.pageCount,
                goPrevious: { goToPage(currentPageIndex - 1) },
                goNext: { goToPage(currentPageIndex + 1) },
                goTo: goToPage,
                export: exportCopy
            )
        }
        .sessionAlerts(session)
        .focusedSceneValue(\.documentSession, session)
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

    // MARK: - Scrollbereich

    /// Breite, die die Seiten nebeneinander brauchen.
    private var contentWidth: CGFloat {
        let pageWidth = session.document.page(at: 0)?.bounds(for: .cropBox).width
            ?? PDFPageFactory.a4.width
        let columns: CGFloat = session.displayMode == .twoUpContinuous ? 2 : 1
        return pageWidth * session.zoom * columns + pageGap * (columns - 1)
    }

    /// Die waagerechte Achse nur einschalten, wenn es etwas zu scrollen gibt.
    /// Sonst zeigt macOS bei fest eingeblendeten Scrollleisten dauerhaft eine
    /// Leiste, die nichts tut — die PDF-Ansicht hat keine.
    private var needsHorizontalScrolling: Bool {
        session.viewportWidth > 0 && contentWidth > session.viewportWidth
    }

    // MARK: - Seitenaufteilung

    /// Eine Zeile der Seitenansicht. Der Anzeigemodus bestimmt, wie viele
    /// Seiten nebeneinander stehen — genau wie in der PDF-Ansicht.
    private struct PageRow: Identifiable {
        let id: UUID
        let indices: [Int]
    }

    private var pageRows: [PageRow] {
        let descriptors = session.pageDescriptors
        return PageLayout.rows(
            pageCount: descriptors.count,
            mode: session.displayMode,
            currentIndex: currentPageIndex
        ).map { PageRow(id: descriptors[$0[0]].id, indices: $0) }
    }

    // MARK: - Seitenlage

    /// Die aktuelle Seite fuehrt die Session — dieselbe, die auch die
    /// PDF-Ansicht benutzt.
    private var currentPageIndex: Int {
        min(max(session.currentPageIndex, 0), max(session.pageDescriptors.count - 1, 0))
    }

    private func goToPage(_ index: Int) {
        guard session.pageDescriptors.indices.contains(index) else { return }
        session.setCurrentPage(index)
        guard session.displayMode != .singlePage else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            visiblePageID = session.pageDescriptors[index].id
        }
    }

    private func followScrollPosition(_ pageID: UUID?) {
        guard session.displayMode != .singlePage,
              let pageID,
              let index = session.pageDescriptors.firstIndex(where: { $0.id == pageID })
        else { return }
        session.setCurrentPage(index)
    }

    /// Beim Moduswechsel wird die Ansicht neu aufgebaut — ohne das faengt
    /// sie wieder oben an.
    private func restoreScrollPosition() {
        guard session.pageDescriptors.indices.contains(currentPageIndex) else { return }
        visiblePageID = session.pageDescriptors[currentPageIndex].id
    }

    private var viewportWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { session.viewportWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in
                    session.viewportWidth = width
                }
        }
    }

    // MARK: - Seiten

    @ViewBuilder
    private func pageView(index: Int) -> some View {
        let size = session.document.page(at: index)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
        let zoom = session.zoom
        let containerIndex = session.notebook.writablePageIndices.firstIndex(of: index)

        NotebookPageView(
            session: session,
            pageIndex: index,
            containerIndex: containerIndex,
            pageSize: size,
            ruling: session.ruling,
            insets: session.notebook.info.textInsets,
            overlayRevision: session.overlayRevision,
            selectedOverlayID: session.selectedOverlayID
        )
        .frame(width: size.width * zoom, height: size.height * zoom)
        .shadow(
            color: .black.opacity(DocumentAppearance.pageShadowOpacity),
            radius: DocumentAppearance.pageShadowRadius,
            y: DocumentAppearance.pageShadowOffset
        )
        // Keine eigene Seitennummer an der Seite: die PDF-Ansicht hat keine,
        // und die Fensterleiste zeigt „x von y“ ohnehin in beiden Modi.
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
    // Dieselbe Leiste wie im Annotationsmodus — `ToolStrip` bringt Hoehe,
    // Polster, Hintergrund und Stil mit. Hier steht nur der Inhalt.

    private var modeToolbar: some View {
        ToolStrip {
            DocumentModePicker(session: session)

            Divider().frame(height: 18)

            Menu {
                Button("Am Ende anhaengen") {
                    session.insertBlankPage()
                }
                Button("Nach Seite \(currentPageIndex + 1) einfuegen") {
                    session.insertBlankPage(after: currentPageIndex)
                }
                .disabled(currentPageIndex + 1 >= session.pageDescriptors.count)
            } label: {
                Label("Seite einfuegen", systemImage: "plus.rectangle.portrait")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Leere Seite einfuegen")

            Button {
                insertImage(onPage: currentPageIndex)
            } label: {
                Label("Bild einfuegen", systemImage: "photo.badge.plus")
            }
            .help("Bild auf der aktuellen Seite einfuegen — oder eine Datei auf die Seite ziehen")

            Divider().frame(height: 18)

            formatToggle("Fett", symbol: "bold", isOn: session.isBoldActive, action: session.toggleBold)
            formatToggle("Kursiv", symbol: "italic", isOn: session.isItalicActive, action: session.toggleItalic)

            Menu {
                ForEach([9, 10, 11, 12, 13, 14, 18, 24, 36], id: \.self) { size in
                    Button("\(size) pt") { session.setFontSize(CGFloat(size)) }
                }
            } label: {
                Label("Schriftgroesse", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 18)

            rulingPicker
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
    }

    /// Zeigt an, ob die Eigenschaft gerade gilt — blau hinterlegt wie die
    /// aktive Auswahl des Modusumschalters.
    private func formatToggle(
        _ label: String,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .frame(width: 24, height: 20)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .help(label)
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
