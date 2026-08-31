//
//  DocumentModePicker.swift
//  BestNotes
//
//  Der Umschalter zwischen Schreiben und Annotieren — einmal definiert,
//  von beiden Leisten benutzt. Getrennte Kopien sind in genau diesem
//  Umschalter schon zweimal auseinandergelaufen.
//

import SwiftUI

struct DocumentModePicker: View {
    @Bindable var session: DocumentSession

    var body: some View {
        Picker("Modus", selection: $session.notebookMode) {
            ForEach(NotebookMode.allCases) { mode in
                Label(mode.label, systemImage: mode.symbol)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        // Der Stil steht hier und nicht an der umgebenden Leiste: sonst
        // haengt das Aussehen davon ab, in welcher Leiste der Umschalter
        // gerade steckt.
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
        .help("Zwischen Schreiben und Annotieren wechseln")
    }
}
