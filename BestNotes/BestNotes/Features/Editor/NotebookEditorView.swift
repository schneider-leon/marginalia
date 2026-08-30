//
//  NotebookEditorView.swift
//  BestNotes
//
//  Der Schreibmodus eines Notizbuchs: Seiten untereinander, durchlaufender
//  Text, der von Seite zu Seite fliesst.
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct NotebookEditorView: View {
    @Bindable var session: DocumentSession

    @State private var failure: ViewerFailure?

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
            .padding(.vertical, pageGap)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) { toolbar }
        .navigationTitle(session.displayName)
        .navigationSubtitle(subtitle)
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

    private var subtitle: String {
        let pages = "\(session.pageDescriptors.count) Seiten"
        return session.hasUnsavedChanges ? "\(pages) — bearbeitet" : pages
    }

    @ViewBuilder
    private func pageView(index: Int, descriptor: PageDescriptor) -> some View {
        let size = session.document.page(at: index)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
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
        .frame(width: size.width, height: size.height)
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

    // MARK: - Werkzeugleiste

    private var toolbar: some View {
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
                insertImage(onPage: session.activePageIndex)
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

            Divider().frame(height: 18)

            Picker("Linien", selection: rulingBinding) {
                ForEach(PageRuling.allCases) { ruling in
                    Text(ruling.label).tag(ruling)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button(action: exportCopy) {
                Label("Exportieren", systemImage: "square.and.arrow.up")
            }
            .help("Als PDF exportieren — getippter Text wird eingebrannt")

            Spacer(minLength: 0)

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

    private var rulingBinding: Binding<PageRuling> {
        Binding(
            get: { session.ruling },
            set: { session.setRuling($0) }
        )
    }
}
