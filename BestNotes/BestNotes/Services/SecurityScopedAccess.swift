//
//  SecurityScopedAccess.swift
//  BestNotes
//
//  Haelt den Sandbox-Zugriff auf eine vom Nutzer gewaehlte Datei offen.
//

import Foundation

/// Besitzt den security-scoped Zugriff auf genau eine URL und gibt ihn
/// spaetestens beim Deinit wieder frei.
///
/// Bewusst eine eigene, nicht actor-isolierte Klasse: `deinit` darf damit
/// aufraeumen, ohne dass wir uns um Isolation der besitzenden `@MainActor`-Typen
/// kuemmern muessen.
final class SecurityScopedAccess {
    private let url: URL
    private var isActive: Bool

    init(url: URL) {
        self.url = url
        self.isActive = url.startAccessingSecurityScopedResource()
    }

    func release() {
        guard isActive else { return }
        url.stopAccessingSecurityScopedResource()
        isActive = false
    }

    deinit {
        release()
    }
}
