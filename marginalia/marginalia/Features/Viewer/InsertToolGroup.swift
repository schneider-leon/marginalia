//
//  InsertToolGroup.swift
//  marginalia
//
//  Inserting a page (both modes) or an image (annotation mode).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The file dialog for images.
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

    var body: some View {
        ToolGroup {
            PageInsertMenu(session: session)
        }
    }
}

/// Only in annotation mode — it sits next to the annotation tools.
struct InsertImageButton: View {
    @Bindable var session: DocumentSession

    @State private var failure: ViewerFailure?

    var body: some View {
        Button(action: insertImage) {
            Label("Insert Image", systemImage: "photo.badge.plus")
                .frame(width: 24, height: 20)
        }
        .help("Insert an image on the current page")
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

        do {
            let page = min(max(session.currentPageIndex, 0), max(session.pageDescriptors.count - 1, 0))
            try session.insertImage(from: url, atPageIndex: page)
        } catch {
            failure = ViewerFailure(error: error)
        }
    }
}
