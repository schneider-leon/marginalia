//
//  FocusedValues+Marginalia.swift
//  marginalia
//
//  Connects the menu bar to the currently active scene without global app
//  state: the scene provides value and action, and the `Commands` pick
//  them up via @FocusedValue.
//

import SwiftUI

extension FocusedValues {
    @Entry var documentSession: DocumentSession?
    @Entry var openDocumentAction: (() -> Void)?
    @Entry var saveDocumentAction: (() -> Void)?
    @Entry var exportDocumentAction: (() -> Void)?
    @Entry var closeTabAction: (() -> Void)?
    @Entry var tabsStore: TabsStore?
    @Entry var toggleSidebarAction: (() -> Void)?
}
