//
//  UTType+BestNotes.swift
//  BestNotes
//

import UniformTypeIdentifiers

extension UTType {
    /// In `Info.plist` als exportierter Typ deklariert, konform zu
    /// `com.apple.package` — der Finder zeigt das Verzeichnis damit als
    /// eine Datei.
    static let bestNotebook = UTType(exportedAs: "app.bestnotes.notebook")

    static let bestNotebookExtension = "bestnote"
}
