//
//  InsertToolGroup.swift
//  BestNotes
//
//  Seite und Bild einfuegen — in beiden Modi dieselbe Gruppe.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Der Dateidialog fuer Bilder — an einer Stelle, weil ihn auch das
/// Kontextmenue einer Seite oeffnet.
@MainActor
enum ImagePicker {
    static func pickImageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.title = "Bild einfuegen"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct InsertToolGroup: View {
    @Bindable var session: DocumentSession

    @State private var failure: ViewerFailure?

    var body: some View {
        ToolGroup {
            PageInsertMenu(session: session)

            ToolGroupDivider()

            Button(action: insertImage) {
                Label("Bild einfuegen", systemImage: "photo.badge.plus")
                    .frame(width: 24, height: 20)
            }
            .help("Bild auf der aktuellen Seite einfuegen — oder eine Datei auf die Seite ziehen")
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.message),
                message: failure.suggestion.map(Text.init),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func insertImage() {
        guard let url = ImagePicker.pickImageURL() else { return }

        // Bilder liegen neben `content.pdf` und werden von der Seitenansicht
        // des Schreibmodus gezeichnet — dort sind auch die Griffe zum
        // Verschieben. Aus dem Annotationsmodus heraus waere das Bild sonst
        // unsichtbar, also wechseln wir mit.
        if session.notebookMode != .write {
            session.notebookMode = .write
        }

        do {
            let page = min(max(session.currentPageIndex, 0), max(session.pageDescriptors.count - 1, 0))
            try session.insertImage(from: url, atPageIndex: page)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }
}
