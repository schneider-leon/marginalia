//
//  HomeView.swift
//  BestNotes
//
//  Die Startseite: zuletzt geoeffnete Dokumente als Raster.
//

import SwiftUI

struct HomeView: View {
    let library: LibraryStore
    let onOpen: (UUID) -> Void
    let onImport: () -> Void

    /// Doppelt so breit wie dargestellt, damit die Miniatur auf einem
    /// Retina-Bildschirm scharf bleibt.
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
        .navigationTitle("BestNotes")
        .navigationSubtitle(recents.isEmpty ? "" : "Zuletzt geoeffnet")
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
                // Kein content.pdf lesbar — Symbol statt leerer Flaeche.
                Image(systemName: node.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        // A4-Verhaeltnis, damit das Raster gleichmaessig bleibt, auch wenn
        // eine Miniatur noch fehlt.
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
            Label("Kein Dokument geoeffnet", systemImage: "doc.richtext")
        } description: {
            Text("Waehle links ein Dokument, oder importiere eine PDF.")
        } actions: {
            Button("PDF importieren …", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}
