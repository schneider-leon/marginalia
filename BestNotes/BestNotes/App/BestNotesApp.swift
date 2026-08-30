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
            // Ab Schritt 4/5 landen hier eigene Menuebefehle
            // (Notizbuch anlegen, PDF importieren, exportieren ...).
            CommandGroup(replacing: .newItem) {}
        }
    }
}
