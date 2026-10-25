//
//  DocumentModePicker.swift
//  marginalia
//
//  The switch between writing and annotating — defined once and used by
//  both toolbars. Separate copies of exactly this switch have already
//  drifted apart twice.
//

import SwiftUI

struct DocumentModePicker: View {
    @Bindable var session: DocumentSession

    var body: some View {
        Picker("Mode", selection: $session.notebookMode) {
            ForEach(NotebookMode.allCases) { mode in
                Label(mode.label, systemImage: mode.symbol)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        // The style lives here and not on the surrounding toolbar: otherwise
        // the look would depend on which toolbar the switch currently sits
        // in.
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
        .help("Switch between writing and annotating")
    }
}
