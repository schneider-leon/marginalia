//
//  PageInsertMenu.swift
//  BestNotes
//
//  Seiten einfuegen — in beiden Modi dasselbe Menue.
//

import SwiftUI

struct PageInsertMenu: View {
    @Bindable var session: DocumentSession

    var body: some View {
        Menu {
            Button("Am Ende anhaengen") {
                session.insertBlankPage()
            }
            Button("Nach Seite \(session.currentPageIndex + 1) einfuegen") {
                session.insertBlankPage(after: session.currentPageIndex)
            }
            .disabled(session.currentPageIndex + 1 >= session.pageDescriptors.count)
        } label: {
            Label("Seite einfuegen", systemImage: "plus.rectangle.portrait")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Leere Seite einfuegen")
    }
}
