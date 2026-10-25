//
//  InsertToolGroup.swift
//  marginalia
//
//  Inserting a page or an image — the same group in both modes.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The file dialog for images — in one place, because a page's context
/// menu opens it too.
@MainActor
enum ImagePicker {
    static func pickImageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.title = "Insert Image"
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
                Label("Insert Image", systemImage: "photo.badge.plus")
                    .frame(width: 24, height: 20)
            }
            .help("Insert an image on the current page — or drag a file onto the page")
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

        // Images live next to `content.pdf` and are drawn by the writing
        // mode's page view — that is also where the handles for moving them
        // are. From annotation mode the image would otherwise be invisible,
        // so we switch along.
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
