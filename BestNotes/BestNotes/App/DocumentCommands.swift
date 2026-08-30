//
//  DocumentCommands.swift
//  BestNotes
//
//  Menuebefehle rund um das aktive Dokument.
//

import SwiftUI

struct DocumentCommands: Commands {
    @FocusedValue(\.openDocumentAction) private var openDocument
    @FocusedValue(\.documentSession) private var session

    var body: some Commands {
        // „Neu“ ergibt erst mit dem Notizbuchformat (Schritt 6) Sinn.
        CommandGroup(replacing: .newItem) {
            Button("PDF oeffnen …") { openDocument?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openDocument == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Vergroessern") { session?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Verkleinern") { session?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Auf Fensterbreite") { session?.fitToWindow() }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Naechste Seite") { session?.goToNextPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(session?.canGoToNextPage != true)
            Button("Vorherige Seite") { session?.goToPreviousPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(session?.canGoToPreviousPage != true)
        }
    }
}
