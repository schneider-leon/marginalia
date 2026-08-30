//
//  CommentSheet.swift
//  BestNotes
//
//  Eingabe fuer einen FreeText-Kommentar. PDFKit kann FreeText-Annotationen
//  nicht inline editieren, also fragen wir den Text ab, bevor die Annotation
//  entsteht.
//

import SwiftUI

struct CommentSheet: View {
    let onCancel: () -> Void
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kommentar")
                .font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .frame(width: 320, height: 110)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }
                .focused($isFocused)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Einfuegen") { onCommit(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear { isFocused = true }
    }
}
