//
//  ToolStrip.swift
//  BestNotes
//
//  Die schmale Werkzeugleiste unter der Tab-Leiste — der Rahmen dafuer gibt
//  es einmal, den Inhalt liefert der jeweilige Modus.
//
//  Sie liegt bewusst *ueber* dem Inhalt und nicht darueber schwebend: als
//  `safeAreaInset` scrollte im Schreibmodus das weisse Papier darunter durch
//  und das Material wurde hell, waehrend die PDF-Ansicht (AppKit) nichts
//  durchscheinen liess. Dieselbe Leiste sah dadurch je nach Modus anders aus.
//

import SwiftUI

struct ToolStrip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
