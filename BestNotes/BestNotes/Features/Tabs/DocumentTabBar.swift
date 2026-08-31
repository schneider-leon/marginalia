//
//  DocumentTabBar.swift
//  BestNotes
//

import SwiftUI

struct DocumentTabBar: View {
    let store: TabsStore
    let onRequestClose: (UUID) -> Void

    @State private var hoveredID: UUID?

    private static let barHeight: CGFloat = 32

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    homeChip
                    ForEach(store.tabs) { tab in
                        chip(for: tab)
                            .id(tab.id)
                    }
                    Spacer(minLength: 0)
                }
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
        // Ohne das waechst die Hervorhebung des aktiven Tabs nach oben in die
        // Sicherheitszone hinein und liegt dann hinter der Fensterleiste.
        .clipped()
        // Wie bei der Werkzeugleiste: ohne undurchsichtige Flaeche dahinter
        // scheint im Schreibmodus das Papier durch — und die Fensterleiste
        // darueber blendet dann in den beiden Modi gegen Verschiedenes.
        .background(.bar)
        .background(Color.documentBackground)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Immer da und nicht schliessbar — deshalb nur ein Symbol, ohne Titel
    /// und ohne Schliessen-Knopf.
    private var homeChip: some View {
        let isActive = store.isShowingHome

        return Image(systemName: "house")
            .imageScale(.medium)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 44)
            .frame(height: Self.barHeight)
            .background(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            .overlay(alignment: .trailing) { Divider() }
            .contentShape(.rect)
            .onTapGesture { store.activateHome() }
            .help("Startseite")
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
        .padding(.horizontal, 10)
        .frame(minWidth: 120, maxWidth: 200)
        .frame(height: Self.barHeight)
        // Wie beim Modusumschalter: die aktive Auswahl ist blau hinterlegt.
        .background(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        .overlay(alignment: .trailing) {
            Divider()
        }
        .contentShape(.rect)
        .onTapGesture { store.activate(tab.id) }
        .onHover { hoveredID = $0 ? tab.id : (hoveredID == tab.id ? nil : hoveredID) }
        .help(tab.title)
        .contextMenu {
            Button("Tab schliessen") { onRequestClose(tab.id) }
            Button("Andere Tabs schliessen") {
                store.tabs.map(\.id).filter { $0 != tab.id }.forEach(onRequestClose)
            }
            .disabled(store.tabs.count < 2)
            Button("Alle Tabs schliessen") {
                store.tabs.map(\.id).forEach(onRequestClose)
            }
        }
    }

    /// Der Punkt fuer ungesicherte Aenderungen wird beim Ueberfahren zum
    /// Schliessen-Knopf — so wie in Xcode und Safari.
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
            .help("Tab schliessen")
        } else if tab.hasUnsavedChanges {
            Circle()
                .fill(.secondary)
                .frame(width: 6, height: 6)
                .frame(width: 14, height: 14)
                .help("Ungesicherte Aenderungen")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }
}
