//
//  FocusedValues+BestNotes.swift
//  BestNotes
//
//  Verbindet die Menueleiste mit der gerade aktiven Szene, ohne globalen
//  App-State: die Szene stellt Wert und Aktion bereit, die `Commands`
//  greifen sie ueber @FocusedValue ab.
//

import SwiftUI

extension FocusedValues {
    @Entry var documentSession: DocumentSession?
    @Entry var openDocumentAction: (() -> Void)?
}
