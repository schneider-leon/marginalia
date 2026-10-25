//
//  UTType+Marginalia.swift
//  marginalia
//

import UniformTypeIdentifiers

extension UTType {
    /// Declared in `Info.plist` as an exported type conforming to
    /// `com.apple.package`, so the Finder shows the directory as a single
    /// file.
    static let marginaliaNotebook = UTType(exportedAs: "app.marginalia.notebook")

    static let marginaliaNotebookExtension = "marginalia"
}
