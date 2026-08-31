//
//  PageLayoutTests.swift
//  BestNotesTests
//

import XCTest
@testable import BestNotes

final class PageLayoutTests: XCTestCase {

    func testFortlaufendGibtEineSeiteProZeile() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 3, mode: .singlePageContinuous, currentIndex: 0),
            [[0], [1], [2]]
        )
    }

    func testEinzelseiteZeigtNurDieAktuelle() {
        XCTAssertEqual(PageLayout.rows(pageCount: 5, mode: .singlePage, currentIndex: 2), [[2]])
    }

    func testEinzelseiteKlemmtEinenUngueltigenIndex() {
        XCTAssertEqual(PageLayout.rows(pageCount: 3, mode: .singlePage, currentIndex: 99), [[2]])
        XCTAssertEqual(PageLayout.rows(pageCount: 3, mode: .singlePage, currentIndex: -4), [[0]])
    }

    func testDoppelseiteMitGeraderAnzahl() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 4, mode: .twoUpContinuous, currentIndex: 0),
            [[0, 1], [2, 3]]
        )
    }

    func testDoppelseiteMitUngeraderAnzahlLaesstDieLetzteAllein() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 5, mode: .twoUpContinuous, currentIndex: 0),
            [[0, 1], [2, 3], [4]]
        )
    }

    func testOhneSeitenGibtEsKeineZeilen() {
        for mode in PageDisplayMode.allCases {
            XCTAssertTrue(PageLayout.rows(pageCount: 0, mode: mode, currentIndex: 0).isEmpty)
        }
    }

    /// Keine Seite darf verschwinden oder doppelt auftauchen.
    func testJedeSeiteGenauEinmal() {
        for count in 1...9 {
            for mode in [PageDisplayMode.singlePageContinuous, .twoUpContinuous] {
                let flat = PageLayout.rows(pageCount: count, mode: mode, currentIndex: 0).flatMap { $0 }
                XCTAssertEqual(flat, Array(0..<count), "\(mode) bei \(count) Seiten")
            }
        }
    }
}
