//
//  ToolStrip.swift
//  BestNotes
//
//  Die schmale Werkzeugleiste unter der Tab-Leiste. Es gibt sie einmal;
//  die beiden Modi liefern nur ihren Inhalt.
//
//  Sie bleibt bewusst ein `safeAreaInset` ueber dem Inhalt — sie an den
//  Inhalt anzustellen sah aus, als haette die Leiste einen Kasten um sich.
//  Damit sie in beiden Modi gleich aussieht, liegt hinter dem Material eine
//  undurchsichtige Flaeche: sonst scheint im Schreibmodus das weisse Papier
//  durch, waehrend die PDF-Ansicht als AppKit-View nichts durchlaesst.
//

import SwiftUI

/// Zusammenhaengende helle Box um eine Gruppe von Werkzeugen — dieselbe
/// Optik wie beim segmentierten Werkzeugwaehler, damit die Leiste in beiden
/// Modi einheitlich wirkt.
struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
    }
}

struct ToolStrip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .background(Color.documentBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}
