//
//  PageLayout.swift
//  BestNotes
//
//  Wie die Seiten im Schreibmodus angeordnet werden — dieselben drei
//  Anzeigemodi, die auch die PDF-Ansicht kennt.
//

import Foundation

enum PageLayout {

    /// Zerlegt die Seiten in Zeilen.
    ///
    /// - Parameter currentIndex: nur im Einzelseitenmodus von Bedeutung; dort
    ///   ist es die einzige gezeigte Seite.
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
