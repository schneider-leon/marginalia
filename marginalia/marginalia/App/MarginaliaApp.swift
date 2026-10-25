//
//  MarginaliaApp.swift
//  marginalia
//

import SwiftData
import SwiftUI

@main
struct MarginaliaApp: App {

    private let container: ModelContainer
    @State private var library: LibraryStore
    private let startupWarning: String?

    init() {
        // If the on-disk store fails, the app keeps running in a fallback
        // mode instead of not starting at all — the documents live next to
        // it as files anyway.
        var warning: String?
        let resolved: ModelContainer
        do {
            resolved = try ModelContainer(for: LibraryEntry.self)
        } catch {
            warning = "The library database could not be opened. "
                + "marginalia is running without saving the folder structure for this session."
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
