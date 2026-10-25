//
//  DocumentTabBar.swift
//  marginalia
//

import SwiftUI

struct DocumentTabBar: View {
    let store: TabsStore
    let onRequestClose: (UUID) -> Void

    @State private var hoveredID: UUID?

    private static let barHeight: CGFloat = 38
    private static let chipHeight: CGFloat = 26

    /// Its own identifier so the home screen can use the same hover state
    /// as the document tabs.
    private static let homeChipID = UUID()

    /// Button look as in the window toolbar: a pill, filled when active,
    /// otherwise only hinted at on hover.
    @ViewBuilder
    private static func chipBackground(isActive: Bool, isHovered: Bool) -> some View {
        if isActive {
            Capsule().fill(Color.accentColor)
        } else if isHovered {
            Capsule().fill(.quaternary)
        } else {
            Capsule().fill(.quaternary.opacity(0.4))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    homeChip
                    ForEach(store.tabs) { tab in
                        chip(for: tab)
                            .id(tab.id)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: Self.barHeight)
            }
            .onChange(of: store.activeID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: Self.barHeight)
        // Without this the active tab's highlight grows upward into the
        // safe area and then sits behind the window toolbar.
        .clipped()
        // As with the tool strip: without an opaque surface behind it, the
        // paper shines through in writing mode — and the window toolbar
        // above then blends against different things in the two modes.
        .background(.bar)
        .background(Color.documentBackground)
    }

    /// Always there and not closable — so just an icon, without a title and
    /// without a close button.
    private var homeChip: some View {
        let isActive = store.isShowingHome

        return Image(systemName: "house")
            .imageScale(.medium)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 38, height: Self.chipHeight)
            .background(Self.chipBackground(isActive: isActive, isHovered: hoveredID == Self.homeChipID))
            .contentShape(.capsule)
            .onTapGesture { store.activateHome() }
            .onHover { hoveredID = $0 ? Self.homeChipID : (hoveredID == Self.homeChipID ? nil : hoveredID) }
            .help("Home")
    }

    private func chip(for tab: DocumentTab) -> some View {
        let isActive = tab.id == store.activeID
        let isHovered = tab.id == hoveredID

        return HStack(spacing: 6) {
            Image(systemName: tab.symbol)
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .imageScale(.small)

            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.callout)
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))

            closeControl(for: tab, revealed: isActive || isHovered)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 100, maxWidth: 200)
        .frame(height: Self.chipHeight)
        // As with the mode switch: the active selection has a blue background.
        .background(Self.chipBackground(isActive: isActive, isHovered: isHovered))
        .contentShape(.capsule)
        .onTapGesture { store.activate(tab.id) }
        .onHover { hoveredID = $0 ? tab.id : (hoveredID == tab.id ? nil : hoveredID) }
        .help(tab.title)
        .contextMenu {
            Button("Close Tab") { onRequestClose(tab.id) }
            Button("Close Other Tabs") {
                store.tabs.map(\.id).filter { $0 != tab.id }.forEach(onRequestClose)
            }
            .disabled(store.tabs.count < 2)
            Button("Close All Tabs") {
                store.tabs.map(\.id).forEach(onRequestClose)
            }
        }
    }

    /// The dot for unsaved changes turns into the close button on hover —
    /// just like in Xcode and Safari.
    @ViewBuilder
    private func closeControl(for tab: DocumentTab, revealed: Bool) -> some View {
        if revealed {
            Button {
                onRequestClose(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(tab.id == store.activeID ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .help("Close Tab")
        } else if tab.hasUnsavedChanges {
            Circle()
                .fill(.secondary)
                .frame(width: 6, height: 6)
                .frame(width: 14, height: 14)
                .help("Unsaved changes")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }
}
