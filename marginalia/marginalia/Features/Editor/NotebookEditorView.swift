//
//  NotebookEditorView.swift
//  marginalia
//
//  The writing mode of a notebook: pages stacked vertically, continuous
//  text that flows from page to page.
//
//  The window toolbar is the same as in the PDF view — page navigation on
//  the left, zoom and export on the right. Only the narrow strip below it
//  carries what belongs to the respective mode.
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
            // Deliberately no LazyVStack: the text views share one layout
            // manager, and a container may only have one view. Throwing them
            // away and rebuilding them while scrolling would be fragile.
            VStack(spacing: pageGap) {
                ForEach(pageRows, id: \.id) { row in
                    HStack(alignment: .top, spacing: pageGap) {
                        ForEach(row.indices, id: \.self) { index in
                            pageView(index: index)
                        }
                    }
                }
            }
            // Without horizontal scrolling fill the width so the pages are
            // centered; otherwise only as wide as needed.
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

    // MARK: - Scroll Area

    /// Width the pages need side by side.
    private var contentWidth: CGFloat {
        let pageWidth = session.document.page(at: 0)?.bounds(for: .cropBox).width
            ?? PDFPageFactory.a4.width
        let columns: CGFloat = session.displayMode == .twoUpContinuous ? 2 : 1
        return pageWidth * session.zoom * columns + pageGap * (columns - 1)
    }

    /// Only turn on the horizontal axis when there is something to scroll.
    /// Otherwise, with always-visible scroll bars, macOS permanently shows a
    /// bar that does nothing — the PDF view has none.
    private var needsHorizontalScrolling: Bool {
        session.viewportWidth > 0 && contentWidth > session.viewportWidth
    }

    // MARK: - Page Layout

    /// One row of the page view. The display mode determines how many pages
    /// sit side by side — just like in the PDF view.
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

    // MARK: - Page Position

    /// The session keeps track of the current page — the same one the PDF
    /// view uses.
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

    /// The view is rebuilt when switching modes — without this it would
    /// start at the top again.
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

    // MARK: - Pages

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
        // No page number of its own on the page: the PDF view has none, and
        // the window toolbar shows "x of y" in both modes anyway.
        .contextMenu {
            Button("Insert Image…") { insertImage(onPage: index) }
            Divider()
            Button("Insert Blank Page After") { session.insertBlankPage(after: index) }
            Button("Delete Page", role: .destructive) { session.removePage(at: index) }
                .disabled(session.pageDescriptors.count < 2)
        }
    }

    // MARK: - Mode Toolbar
    //
    // The same strip as in annotation mode — `ToolStrip` brings height,
    // padding, background and style. Only the content lives here.

    private var modeToolbar: some View {
        ToolStrip {
            DocumentModePicker(session: session)

            Divider().frame(height: 18)

            InsertToolGroup(session: session)

            Divider().frame(height: 18)

            formatGroup

            alignmentGroup

            Divider().frame(height: 18)

            rulingPicker
                .fixedSize()

            Spacer(minLength: 0)

            if !session.loadWarnings.isEmpty {
                Button {
                    showsLoadWarnings = true
                } label: {
                    Label("Notices", systemImage: "exclamationmark.triangle.fill")
                }
                .help("Something was repaired while opening")
                .popover(isPresented: $showsLoadWarnings, arrowEdge: .bottom) {
                    loadWarningsPopover
                }
            }

            if session.hasUnsavedChanges {
                Text("Not Saved")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Look of the tool picker in annotation mode: one continuous light box,
    /// with the active properties in blue.
    private var formatGroup: some View {
        ToolGroup {
            formatToggle("Bold", symbol: "bold", isOn: session.isBoldActive, action: session.toggleBold)
            ToolGroupDivider()
            formatToggle("Italic", symbol: "italic", isOn: session.isItalicActive, action: session.toggleItalic)
            ToolGroupDivider()
            formatToggle(
                "Underline", symbol: "underline",
                isOn: session.isUnderlineActive, action: session.toggleUnderline
            )
            ToolGroupDivider()

            Menu {
                ForEach([9, 10, 11, 12, 13, 14, 18, 24, 36], id: \.self) { size in
                    Button("\(size) pt") { session.setFontSize(CGFloat(size)) }
                }
            } label: {
                Label("Font Size", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Font size")
        }
    }

    private var alignmentGroup: some View {
        ToolGroup {
            alignmentToggle("Align Left", symbol: "text.alignleft", alignment: .left)
            ToolGroupDivider()
            alignmentToggle("Center", symbol: "text.aligncenter", alignment: .center)
            ToolGroupDivider()
            alignmentToggle("Align Right", symbol: "text.alignright", alignment: .right)
        }
    }

    private func alignmentToggle(
        _ label: String,
        symbol: String,
        alignment: NSTextAlignment
    ) -> some View {
        formatToggle(
            label,
            symbol: symbol,
            isOn: session.currentAlignment == alignment,
            action: { session.setAlignment(alignment) }
        )
    }

    /// Shows whether the property currently applies — with a blue background
    /// like the active selection of the mode switch.
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
            Text("Repaired While Opening")
                .font(.headline)
            ForEach(session.loadWarnings, id: \.self) { warning in
                Label(warning, systemImage: "wrench.adjustable")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Got It") {
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
        Picker("Lines", selection: rulingBinding) {
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

    // MARK: - Actions

    private func saveInPlace() {
        guard session.hasUnsavedChanges else { return }
        do { try session.save() } catch { failure = ViewerFailure(error: error) }
    }

    private func exportCopy() {
        do { try session.exportCopy() } catch { failure = ViewerFailure(error: error) }
    }

    private func insertImage(onPage index: Int) {
        guard let url = ImagePicker.pickImageURL() else { return }
        do {
            let page = min(max(index, 0), max(session.pageDescriptors.count - 1, 0))
            try session.insertImage(from: url, atPageIndex: page)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }
}
