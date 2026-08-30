//
//  BestNotesApp.swift
//  BestNotes
//

import SwiftData
import SwiftUI

@main
struct BestNotesApp: App {

    private let container: ModelContainer
    @State private var library: LibraryStore
    private let startupWarning: String?

    init() {
        // Faellt der Speicher auf der Platte aus, laeuft die App im
        // Notbetrieb weiter statt gar nicht zu starten — die Dokumente
        // liegen ohnehin als Dateien daneben.
        var warning: String?
        let resolved: ModelContainer
        do {
            resolved = try ModelContainer(for: LibraryEntry.self)
        } catch {
            warning = "Die Bibliotheksdatenbank konnte nicht geoeffnet werden. "
                + "BestNotes laeuft in dieser Sitzung ohne Speicherung der Ordnerstruktur."
            resolved = try! ModelContainer(
                for: LibraryEntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        container = resolved
        startupWarning = warning
        _library = State(initialValue: LibraryStore(context: resolved.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView(library: library, startupWarning: startupWarning)
        }
        .defaultSize(width: 1280, height: 820)
        .modelContainer(container)
        .commands {
            DocumentCommands()
        }
    }
}
