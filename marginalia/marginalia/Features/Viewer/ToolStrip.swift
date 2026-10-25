//
//  ToolStrip.swift
//  marginalia
//
//  The narrow toolbar below the tab bar. It exists once; the two modes
//  only provide its content.
//
//  It deliberately stays a `safeAreaInset` above the content — attaching it
//  to the content looked as if the bar had a box around it. So it looks the
//  same in both modes, an opaque surface sits behind the material:
//  otherwise the white paper would shine through in writing mode, while the
//  PDF view, being an AppKit view, lets nothing through.
//

import SwiftUI

/// Continuous light box around a group of tools — the same look as the
/// segmented tool picker, so the toolbar looks consistent in both modes.
struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
    }
}

/// Divider between two tools inside a `ToolGroup` — as short as the
/// dividers of a segmented picker.
///
/// Deliberately placed by hand instead of inserted automatically between
/// all children: that would require `ToolGroup` to break up its content,
/// which is only possible through non-public SwiftUI internals.
struct ToolGroupDivider: View {
    var body: some View {
        Divider()
            .frame(height: 14)
    }
}

struct ToolStrip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .background(Color.documentBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}
