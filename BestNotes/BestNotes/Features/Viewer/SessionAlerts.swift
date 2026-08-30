//
//  SessionAlerts.swift
//  BestNotes
//
//  Meldungen, die jedes offene Dokument zeigen kann — unabhaengig davon, ob
//  es gerade im Editor oder im PDF-Viewer steckt.
//

import SwiftUI

private struct SessionAlertsModifier: ViewModifier {
    @Bindable var session: DocumentSession

    func body(content: Content) -> some View {
        content.alert(
            "Sichern fehlgeschlagen",
            isPresented: Binding(
                get: { session.saveError != nil },
                set: { if !$0 { session.saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.saveError = nil }
        } message: {
            Text(session.saveError ?? "")
                + Text("\n\nDas Dokument bleibt geoeffnet, damit nichts verlorengeht.")
        }
    }
}

extension View {
    func sessionAlerts(_ session: DocumentSession) -> some View {
        modifier(SessionAlertsModifier(session: session))
    }
}
