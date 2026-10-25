//
//  PageLayoutTests.swift
//  marginaliaTests
//

import XCTest
@testable import marginalia

final class PageLayoutTests: XCTestCase {

    func testContinuousGivesOnePagePerRow() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 3, mode: .singlePageContinuous, currentIndex: 0),
            [[0], [1], [2]]
        )
    }

    func testSinglePageShowsOnlyTheCurrentOne() {
        XCTAssertEqual(PageLayout.rows(pageCount: 5, mode: .singlePage, currentIndex: 2), [[2]])
    }

    func testSinglePageClampsAnInvalidIndex() {
        XCTAssertEqual(PageLayout.rows(pageCount: 3, mode: .singlePage, currentIndex: 99), [[2]])
        XCTAssertEqual(PageLayout.rows(pageCount: 3, mode: .singlePage, currentIndex: -4), [[0]])
    }

    func testTwoUpWithEvenCount() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 4, mode: .twoUpContinuous, currentIndex: 0),
            [[0, 1], [2, 3]]
        )
    }

    func testTwoUpWithOddCountLeavesTheLastOneAlone() {
        XCTAssertEqual(
            PageLayout.rows(pageCount: 5, mode: .twoUpContinuous, currentIndex: 0),
            [[0, 1], [2, 3], [4]]
        )
    }

    func testNoPagesGiveNoRows() {
        for mode in PageDisplayMode.allCases {
            XCTAssertTrue(PageLayout.rows(pageCount: 0, mode: mode, currentIndex: 0).isEmpty)
        }
    }

    /// No page may disappear or show up twice.
    func testEveryPageExactlyOnce() {
        for count in 1...9 {
            for mode in [PageDisplayMode.singlePageContinuous, .twoUpContinuous] {
                let flat = PageLayout.rows(pageCount: count, mode: mode, currentIndex: 0).flatMap { $0 }
                XCTAssertEqual(flat, Array(0..<count), "\(mode) with \(count) pages")
            }
        }
    }
}
