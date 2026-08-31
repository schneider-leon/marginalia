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
    ///
    /// Bewusst selbst definiert statt `underPageBackgroundColor`: eine
    /// dynamische Systemfarbe kann von AppKit und SwiftUI unterschiedlich
    /// aufgeloest werden, und dann wechselt der Hintergrund beim Umschalten
    /// zwischen den Modi. Mit festen Werten kann das nicht passieren.
    static let documentBackground = NSColor(name: "documentBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.14, alpha: 1)
            : NSColor(calibratedWhite: 0.85, alpha: 1)
    }
}

extension Color {
    static var documentBackground: Color { Color(nsColor: .documentBackground) }
}

enum DocumentAppearance {
    /// Abstand um und zwischen den Seiten — in beiden Modi derselbe, damit
    /// die Seite beim Umschalten nicht springt.
    static let pageGap: CGFloat = 24
}
