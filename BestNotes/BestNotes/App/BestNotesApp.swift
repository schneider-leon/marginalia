//
//  BestNotesApp.swift
//  BestNotes
//

import SwiftUI

@main
struct BestNotesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            DocumentCommands()
        }
    }
}
