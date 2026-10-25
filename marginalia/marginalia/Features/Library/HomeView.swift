//
//  HomeView.swift
//  marginalia
//
//  The home screen: recently opened documents as a grid.
//

import SwiftUI

struct HomeView: View {
    let library: LibraryStore
    let onOpen: (UUID) -> Void
    let onImport: () -> Void

    /// Twice as wide as displayed so the thumbnail stays sharp on a Retina
    /// display.
    private static let thumbnailWidth: CGFloat = 170
    private static let renderWidth: CGFloat = 340

    var body: some View {
        let recents = library.recentlyOpened()

        Group {
            if recents.isEmpty {
                emptyState
            } else {
                grid(recents)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("marginalia")
        .navigationSubtitle(recents.isEmpty ? "" : "Recently Opened")
    }

    private func grid(_ recents: [LibraryNode]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.thumbnailWidth, maximum: 220), spacing: 24)],
                alignment: .leading,
                spacing: 24
            ) {
                ForEach(recents) { node in
                    card(for: node)
                }
            }
            .padding(28)
        }
    }

    private func card(for node: LibraryNode) -> some View {
        Button {
            onOpen(node.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail(for: node)

                Text(node.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)

                if let opened = node.lastOpenedAt {
                    Text(opened, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .help(node.name)
    }

    @ViewBuilder
    private func thumbnail(for node: LibraryNode) -> some View {
        let image = DocumentThumbnails.shared.thumbnail(for: node.id, width: Self.renderWidth)

        ZStack {
            Color.white
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // No readable content.pdf — an icon instead of an empty area.
                Image(systemName: node.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        // A4 ratio so the grid stays even, even while a thumbnail is still
        // missing.
        .aspectRatio(1 / 1.414, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(
            color: .black.opacity(DocumentAppearance.pageShadowOpacity),
            radius: DocumentAppearance.pageShadowRadius,
            y: DocumentAppearance.pageShadowOffset
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Document Open", systemImage: "doc.richtext")
        } description: {
            Text("Choose a document on the left, or import a PDF.")
        } actions: {
            Button("Import PDF…", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}
