//
//  DocumentCommands.swift
//  marginalia
//
//  Menu commands around the active document. The commands reach the
//  active scene via @FocusedValue — no global app state.
//

import SwiftUI

struct DocumentCommands: Commands {
    @FocusedValue(\.openDocumentAction) private var openDocument
    @FocusedValue(\.saveDocumentAction) private var saveDocument
    @FocusedValue(\.exportDocumentAction) private var exportDocument
    @FocusedValue(\.documentSession) private var session
    @FocusedValue(\.closeTabAction) private var closeTab
    @FocusedValue(\.tabsStore) private var tabs
    @FocusedValue(\.toggleSidebarAction) private var toggleSidebar

    var body: some Commands {
        // "New" only makes sense once the notebook format exists (step 6).
        CommandGroup(replacing: .newItem) {
            Button("Import PDF…") { openDocument?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openDocument == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { saveDocument?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(session?.hasUnsavedChanges != true)

            Button("Export as PDF…") { exportDocument?() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportDocument == nil)
        }

        // The built-in items are tied to SwiftUI's own UndoManager; our
        // annotations go through the session's.
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { session?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session?.canUndo != true)

            Button(redoTitle) { session?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(session?.canRedo != true)
        }

        CommandMenu("Tools") {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    session?.activeTool = tool
                } label: {
                    Label(tool.label, systemImage: tool.symbol)
                }
                // Control instead of Command: ⌘1–⌘9 belong to the tabs.
                .keyboardShortcut(tool.shortcut, modifiers: .control)
                .disabled(session == nil)
            }
        }

        CommandMenu("Tabs") {
            Button("Next Tab") { tabs?.activateNext() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { tabs?.activatePrevious() }
                .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button("Close Tab") { closeTab?() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(closeTab == nil || tabs?.isEmpty != false)

            if let tabs, !tabs.isEmpty {
                Divider()
                ForEach(Array(tabs.tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                    Button(tab.title) { tabs.activate(index: index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Show/Hide Library") { toggleSidebar?() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(toggleSidebar == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") { session?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { session?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Fit to Window Width") { session?.fitToWindow() }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Next Page") { session?.goToNextPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(session?.canGoToNextPage != true)
            Button("Previous Page") { session?.goToPreviousPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(session?.canGoToPreviousPage != true)
        }
    }

    private var undoTitle: String {
        guard let name = session?.undoManager.undoActionName, !name.isEmpty else {
            return "Undo"
        }
        return "Undo \(name)"
    }

    private var redoTitle: String {
        guard let name = session?.undoManager.redoActionName, !name.isEmpty else {
            return "Redo"
        }
        return "Redo \(name)"
    }
}
