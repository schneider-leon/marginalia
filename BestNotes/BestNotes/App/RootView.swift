//
//  RootView.swift
//  BestNotes
//
//  Wurzel-Layout der App. Aktuell nur ein Geruest:
//  links die spaetere Bibliothek (Schritt 4), rechts der
//  Dokumentbereich mit Tab-Leiste (Schritt 5) und Viewer (Schritt 2).
//

import SwiftUI

struct RootView: View {
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            PlaceholderPane(
                symbol: "sidebar.leading",
                title: "Bibliothek",
                subtitle: "Ordner & Notizbuecher — Schritt 4"
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            PlaceholderPane(
                symbol: "doc.richtext",
                title: "Kein Dokument geoeffnet",
                subtitle: "PDF-Viewer — Schritt 2"
            )
        }
        .navigationTitle("BestNotes")
    }
}

private struct PlaceholderPane: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(subtitle)
        }
    }
}

#Preview {
    RootView()
}
