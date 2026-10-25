//
//  PageInsertMenu.swift
//  marginalia
//
//  Inserting pages — the same menu in both modes.
//

import SwiftUI

struct PageInsertMenu: View {
    @Bindable var session: DocumentSession

    var body: some View {
        Menu {
            Button("Append at End") {
                session.insertBlankPage()
            }
            Button("Insert After Page \(session.currentPageIndex + 1)") {
                session.insertBlankPage(after: session.currentPageIndex)
            }
            .disabled(session.currentPageIndex + 1 >= session.pageDescriptors.count)
        } label: {
            Label("Insert Page", systemImage: "plus.rectangle.portrait")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Insert a blank page")
    }
}
