//
//  DocumentToolbarControls.swift
//  marginalia
//
//  The window toolbar — defined once, used by both modes.
//
//  `DocumentToolbarContent` is deliberately `ToolbarContent` and not a
//  collection of individual views: that way the toolbar cannot drift apart
//  between the PDF view and writing mode, because it only exists once.
//

import SwiftUI

struct DocumentToolbarContent: ToolbarContent {
    @Bindable var session: DocumentSession

    let currentIndex: Int
    let pageCount: Int
    let goPrevious: () -> Void
    let goNext: () -> Void
    let goTo: (Int) -> Void
    let export: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            PageNavigationControls(
                currentIndex: currentIndex,
                pageCount: pageCount,
                goPrevious: goPrevious,
                goNext: goNext,
                goTo: goTo
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ZoomControls(
                scale: session.currentScale,
                canZoomIn: session.canZoomIn,
                canZoomOut: session.canZoomOut,
                zoomIn: session.zoomIn,
                zoomOut: session.zoomOut,
                fit: session.fitToWindow
            )

            Picker("Display", selection: $session.displayMode) {
                ForEach(PageDisplayMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Button(action: export) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export as PDF")
        }
    }
}

struct PageNavigationControls: View {
    let currentIndex: Int
    let pageCount: Int
    let goPrevious: () -> Void
    let goNext: () -> Void
    let goTo: (Int) -> Void

    @State private var fieldText = "1"

    var body: some View {
        // Spacing set individually instead of evenly: the counter moves
        // closer to the arrow, and the pill keeps its width because the same
        // amount is added back on the right.
        HStack(spacing: 0) {
            Button(action: goPrevious) {
                Label("Previous Page", systemImage: "chevron.up")
            }
            .disabled(currentIndex <= 0)
            .padding(.trailing, 4)

            Button(action: goNext) {
                Label("Next Page", systemImage: "chevron.down")
            }
            .disabled(currentIndex + 1 >= pageCount)

            pageField
        }
        .fixedSize()
        .onAppear(perform: sync)
        .onChange(of: currentIndex) { sync() }
        .onChange(of: pageCount) { sync() }
    }

    /// Number and total live in *one* element.
    ///
    /// No border of its own: the window toolbar already draws one around
    /// every element, and a second one inside would be smaller — the outer
    /// one would then peek out all around. Because both parts belong to one
    /// element, the toolbar cannot pull them apart either.
    private var pageField: some View {
        HStack(spacing: 4) {
            TextField("", text: $fieldText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: digitWidth)
                .onSubmit(commit)

            Text("of \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        // The window toolbar wraps its capsule tightly around the content;
        // without this the total touches the right edge. Together with the
        // missing spacing on the left, the pill keeps its width.
        .padding(.trailing, 12)
        .fixedSize()
    }

    /// Width based on the largest possible page number so the field does not
    /// jump while paging.
    private var digitWidth: CGFloat {
        CGFloat(max(2, String(max(pageCount, 1)).count)) * 9
    }

    private func sync() {
        fieldText = String(currentIndex + 1)
    }

    private func commit() {
        if let number = Int(fieldText.trimmingCharacters(in: .whitespaces)),
           (1...max(pageCount, 1)).contains(number) {
            goTo(number - 1)
        }
        sync()
    }
}

struct ZoomControls: View {
    let scale: CGFloat
    let canZoomIn: Bool
    let canZoomOut: Bool
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let fit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: zoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(!canZoomOut)

            Button(action: fit) {
                Text("\(Int((scale * 100).rounded()))\u{00A0}%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help("Fit to window width")

            Button(action: zoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(!canZoomIn)
        }
        .fixedSize()
    }
}
