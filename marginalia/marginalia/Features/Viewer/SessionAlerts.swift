//
//  SessionAlerts.swift
//  marginalia
//
//  Alerts any open document can show — regardless of whether it is
//  currently in the editor or in the PDF viewer.
//

import SwiftUI

private struct SessionAlertsModifier: ViewModifier {
    @Bindable var session: DocumentSession

    func body(content: Content) -> some View {
        content.alert(
            "Saving Failed",
            isPresented: Binding(
                get: { session.saveError != nil },
                set: { if !$0 { session.saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.saveError = nil }
        } message: {
            Text(session.saveError ?? "")
                + Text("\n\nThe document stays open so nothing is lost.")
        }
    }
}

extension View {
    func sessionAlerts(_ session: DocumentSession) -> some View {
        modifier(SessionAlertsModifier(session: session))
    }
}
