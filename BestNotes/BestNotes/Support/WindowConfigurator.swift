//
//  WindowConfigurator.swift
//  BestNotes
//
//  Zugriff auf das `NSWindow` hinter einer SwiftUI-Szene, fuer die paar
//  Einstellungen, die SwiftUI nicht anbietet.
//

import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    /// Wendet die Einstellung an, sobald die View tatsaechlich in einem
    /// Fenster haengt. Ein einmaliger Versuch beim Erzeugen greift nicht —
    /// da gibt es das Fenster noch nicht.
    final class ProbeView: NSView {
        var configure: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure?(window) }
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView(frame: .zero)
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.configure = configure
        if let window = nsView.window { configure(window) }
    }
}

extension View {
    func configureWindow(_ configure: @escaping (NSWindow) -> Void) -> some View {
        background(WindowConfigurator(configure: configure))
    }
}
