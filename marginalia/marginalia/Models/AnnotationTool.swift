//
//  AnnotationTool.swift
//  marginalia
//

import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    /// Normal reading: text selection, links, no interference with mouse events.
    case select
    /// The text selection is turned into highlight annotations on mouse up.
    case highlight
    /// Freehand stroke as an ink annotation.
    case ink
    /// A dragged-out box with typed text — a sticky note.
    case text
    /// A click removes the annotation that was hit.
    case eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .ink: "Freehand"
        case .text: "Sticky Note"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .ink: "pencil.tip"
        case .text: "note.text"
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

    /// Tools that need the PDFView's built-in text selection.
    var usesTextSelection: Bool {
        self == .select || self == .highlight
    }
}

/// Look of the next annotation created.
struct AnnotationStyle {
    var highlightColor: Color = .yellow
    var inkColor: Color = .red
    var inkWidth: CGFloat = 2
    var textColor: Color = .black
    var textSize: CGFloat = 13
    /// Background of the sticky note.
    var noteColor: Color = Color(red: 1.0, green: 0.90, blue: 0.55)

    var highlightNSColor: NSColor { NSColor(highlightColor).withAlphaComponent(0.35) }
    var inkNSColor: NSColor { NSColor(inkColor) }
    var textNSColor: NSColor { NSColor(textColor) }
    var noteNSColor: NSColor { NSColor(noteColor) }

    /// Size of a note the user only clicked instead of dragging out.
    static let defaultNoteSize = CGSize(width: 180, height: 90)
    /// Below this size a drag counts as a click.
    static let minimumNoteSize = CGSize(width: 40, height: 28)
}
