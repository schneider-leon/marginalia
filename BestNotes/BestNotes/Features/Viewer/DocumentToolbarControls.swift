//
//  DocumentToolbarControls.swift
//  BestNotes
//
//  Die Bedienelemente der Fensterleiste. Beide Modi — PDF-Ansicht und
//  Schreibmodus — benutzen dieselben Bausteine, damit die Leiste beim
//  Umschalten nicht die Form wechselt.
//

import SwiftUI

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

            TextField("Seite", text: $fieldText)
                .textFieldStyle(.roundedBorder)
                // Zentriert statt rechtsbuendig: sonst klebt die Zahl am Rand.
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 46)
                .onSubmit(commit)

            Text("von \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        // Ohne das zieht die Fensterleiste die Gruppe auseinander und „von N“
        // rutscht vom Eingabefeld weg an den rechten Rand.
        .fixedSize()
        .onAppear(perform: sync)
        .onChange(of: currentIndex) { sync() }
        .onChange(of: pageCount) { sync() }
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
    let fitHelp: String

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
            .help(fitHelp)

            Button(action: zoomIn) {
                Label("Vergroessern", systemImage: "plus.magnifyingglass")
            }
            .disabled(!canZoomIn)
        }
    }
}
