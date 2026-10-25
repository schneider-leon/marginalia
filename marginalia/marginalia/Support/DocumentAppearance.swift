//
//  DocumentAppearance.swift
//  marginalia
//
//  Shared look of the document area. Both modes take their values from
//  here so the background does not change when switching.
//

import AppKit
import SwiftUI

extension NSColor {
    /// Area behind the pages.
    ///
    /// Deliberately defined here instead of `underPageBackgroundColor`: a
    /// dynamic system color can be resolved differently by AppKit and
    /// SwiftUI, and then the background changes when switching between the
    /// modes. With fixed values that cannot happen.
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
    /// Spacing around and between the pages — the same in both modes so the
    /// page does not jump when switching.
    static let pageGap: CGFloat = 24

    /// Shadow under a page.
    ///
    /// In writing mode we draw it ourselves; in the PDF view PDFKit does.
    /// The values are tuned to its subtler shadow — it cannot be reproduced
    /// exactly because PDFKit draws it internally.
    static let pageShadowRadius: CGFloat = 4
    static let pageShadowOpacity: Double = 0.3
    static let pageShadowOffset: CGFloat = 1
}
