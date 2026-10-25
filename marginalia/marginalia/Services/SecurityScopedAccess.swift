//
//  SecurityScopedAccess.swift
//  marginalia
//
//  Keeps sandbox access to a file chosen by the user open.
//

import Foundation

/// Owns the security-scoped access to exactly one URL and releases it at
/// the latest on deinit.
///
/// Deliberately a separate, non-actor-isolated class: this lets `deinit`
/// clean up without us having to worry about the isolation of the owning
/// `@MainActor` types.
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
