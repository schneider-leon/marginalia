//
//  DocumentAppearance.swift
//  BestNotes
//
//  Gemeinsames Aussehen des Dokumentbereichs. Beide Modi holen ihre Werte
//  hier, damit der Hintergrund beim Umschalten nicht wechselt.
//

import AppKit
import SwiftUI

extension NSColor {
    /// Flaeche hinter den Seiten.
    static var documentBackground: NSColor { .underPageBackgroundColor }
}

extension Color {
    static var documentBackground: Color { Color(nsColor: .documentBackground) }
}
