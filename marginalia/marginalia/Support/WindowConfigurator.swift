//
//  WindowConfigurator.swift
//  marginalia
//
//  Access to the `NSWindow` behind a SwiftUI scene, for the few settings
//  SwiftUI does not offer.
//

import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    /// Applies the setting as soon as the view actually sits in a window.
    /// A one-time attempt on creation does not work — the window does not
    /// exist yet at that point.
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
