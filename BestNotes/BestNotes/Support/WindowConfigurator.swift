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

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Beim Erzeugen haengt die View noch an keinem Fenster.
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}

extension View {
    func configureWindow(_ configure: @escaping (NSWindow) -> Void) -> some View {
        background(WindowConfigurator(configure: configure))
    }
}
