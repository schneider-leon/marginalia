//
//  DocumentToolbarControls.swift
//  BestNotes
//
//  Die Fensterleiste — einmal definiert, von beiden Modi benutzt.
//
//  `DocumentToolbarContent` ist bewusst `ToolbarContent` und keine Sammlung
//  einzelner Views: so kann die Leiste zwischen PDF-Ansicht und Schreibmodus
//  nicht auseinanderlaufen, weil es sie nur einmal gibt.
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

            Picker("Anzeige", selection: $session.displayMode) {
                ForEach(PageDisplayMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Button(action: export) {
                Label("Exportieren", systemImage: "square.and.arrow.up")
            }
            .help("Als PDF exportieren")
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
        HStack(spacing: 4) {
            Button(action: goPrevious) {
                Label("Vorherige Seite", systemImage: "chevron.up")
            }
            .disabled(currentIndex <= 0)

            Button(action: goNext) {
                Label("Naechste Seite", systemImage: "chevron.down")
            }
            .disabled(currentIndex + 1 >= pageCount)

            pageField
        }
        .fixedSize()
        .onAppear(perform: sync)
        .onChange(of: currentIndex) { sync() }
        .onChange(of: pageCount) { sync() }
    }

    /// Zahl und Gesamtzahl stecken in *einem* Element.
    ///
    /// Kein eigener Rahmen: die Fensterleiste zeichnet um jedes Element schon
    /// einen, und ein zweiter darin liegender waere kleiner — der aeussere
    /// schaut dann ringsum heraus. Weil beide Teile zu einem Element gehoeren,
    /// kann die Leiste sie auch nicht auseinanderziehen.
    private var pageField: some View {
        HStack(spacing: 4) {
            TextField("", text: $fieldText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: digitWidth)
                .onSubmit(commit)

            Text("von \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        // Die Fensterleiste legt ihre Kapsel eng um den Inhalt; ohne das
        // beruehrt die Gesamtzahl den rechten Rand.
        .padding(.trailing, 8)
        .fixedSize()
    }

    /// Breite nach der groessten vorkommenden Seitenzahl, damit das Feld beim
    /// Blaettern nicht springt.
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
                Label("Verkleinern", systemImage: "minus.magnifyingglass")
            }
            .disabled(!canZoomOut)

            Button(action: fit) {
                Text("\(Int((scale * 100).rounded()))\u{00A0}%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help("Auf Fensterbreite anpassen")

            Button(action: zoomIn) {
                Label("Vergroessern", systemImage: "plus.magnifyingglass")
            }
            .disabled(!canZoomIn)
        }
        .fixedSize()
    }
}
