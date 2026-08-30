//
//  DocumentCommands.swift
//  BestNotes
//
//  Menuebefehle rund um das aktive Dokument. Die Befehle greifen ueber
//  @FocusedValue auf die aktive Szene zu — kein globaler App-State.
//

import SwiftUI

struct DocumentCommands: Commands {
    @FocusedValue(\.openDocumentAction) private var openDocument
    @FocusedValue(\.saveDocumentAction) private var saveDocument
    @FocusedValue(\.exportDocumentAction) private var exportDocument
    @FocusedValue(\.documentSession) private var session

    var body: some Commands {
        // „Neu“ ergibt erst mit dem Notizbuchformat (Schritt 6) Sinn.
        CommandGroup(replacing: .newItem) {
            Button("PDF importieren …") { openDocument?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openDocument == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Sichern") { saveDocument?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(session?.hasUnsavedChanges != true)

            Button("Als PDF exportieren …") { exportDocument?() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportDocument == nil)
        }

        // Die eingebauten Eintraege haengen an SwiftUIs eigenem UndoManager;
        // unsere Annotationen laufen ueber den der Session.
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { session?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session?.canUndo != true)

            Button(redoTitle) { session?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(session?.canRedo != true)
        }

        CommandMenu("Werkzeuge") {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    session?.activeTool = tool
                } label: {
                    Label(tool.label, systemImage: tool.symbol)
                }
                .keyboardShortcut(tool.shortcut, modifiers: .command)
                .disabled(session == nil)
            }
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

    private var undoTitle: String {
        guard let name = session?.undoManager.undoActionName, !name.isEmpty else {
            return "Widerrufen"
        }
        return "\(name) widerrufen"
    }

    private var redoTitle: String {
        guard let name = session?.undoManager.redoActionName, !name.isEmpty else {
            return "Wiederholen"
        }
        return "\(name) wiederholen"
    }
}
