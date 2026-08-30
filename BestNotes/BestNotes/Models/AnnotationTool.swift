//
//  AnnotationTool.swift
//  BestNotes
//

import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    /// Normales Lesen: Textauswahl, Links, kein Eingriff in die Mausereignisse.
    case select
    /// Textauswahl wird beim Loslassen in Highlight-Annotationen umgewandelt.
    case highlight
    /// Freihandstrich als Ink-Annotation.
    case ink
    /// Klick setzt einen getippten Kommentar (FreeText-Annotation).
    case text
    /// Klick entfernt die getroffene Annotation.
    case eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Auswahl"
        case .highlight: "Markieren"
        case .ink: "Freihand"
        case .text: "Kommentar"
        case .eraser: "Radierer"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .ink: "pencil.tip"
        case .text: "text.bubble"
        case .eraser: "eraser"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .select: "1"
        case .highlight: "2"
        case .ink: "3"
        case .text: "4"
        case .eraser: "5"
        }
    }

    /// Werkzeuge, die die eingebaute Textauswahl der PDFView brauchen.
    var usesTextSelection: Bool {
        self == .select || self == .highlight
    }
}

/// Aussehen der naechsten erzeugten Annotation.
struct AnnotationStyle {
    var highlightColor: Color = .yellow
    var inkColor: Color = .red
    var inkWidth: CGFloat = 2
    var textColor: Color = .black
    var textSize: CGFloat = 13

    var highlightNSColor: NSColor { NSColor(highlightColor).withAlphaComponent(0.35) }
    var inkNSColor: NSColor { NSColor(inkColor) }
    var textNSColor: NSColor { NSColor(textColor) }
}
