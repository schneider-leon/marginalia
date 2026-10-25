//
//  PageLayout.swift
//  marginalia
//
//  How pages are arranged in writing mode — the same three display modes
//  the PDF view knows.
//

import Foundation

enum PageLayout {

    /// Splits the pages into rows.
    ///
    /// - Parameter currentIndex: only relevant in single-page mode, where it
    ///   is the only page shown.
    static func rows(pageCount: Int, mode: PageDisplayMode, currentIndex: Int) -> [[Int]] {
        guard pageCount > 0 else { return [] }

        switch mode {
        case .singlePage:
            let clamped = min(max(currentIndex, 0), pageCount - 1)
            return [[clamped]]

        case .singlePageContinuous:
            return (0..<pageCount).map { [$0] }

        case .twoUpContinuous:
            return stride(from: 0, to: pageCount, by: 2).map { start in
                Array(start..<min(start + 2, pageCount))
            }
        }
    }
}
