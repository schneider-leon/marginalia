//
//  TabsStoreTests.swift
//  marginaliaTests
//

import XCTest
@testable import marginalia

@MainActor
final class TabsStoreTests: XCTestCase {

    private let a = LibraryNode.notebook("A")
    private let b = LibraryNode.notebook("B")
    private let c = LibraryNode.notebook("C")

    private func makeStore() throws -> TabsStore {
        let store = TabsStore()
        try store.open(a)
        try store.open(b)
        try store.open(c)
        return store
    }

    func testHomeIsTheInitialState() throws {
        let store = TabsStore()
        XCTAssertTrue(store.isShowingHome)
        XCTAssertNil(store.activeTab)

        try store.open(a)
        XCTAssertFalse(store.isShowingHome)

        store.activateHome()
        XCTAssertTrue(store.isShowingHome)
        XCTAssertNil(store.activeTab)
        XCTAssertEqual(store.tabs.count, 1, "The home screen does not replace a tab")

        store.activate(a.id)
        XCTAssertFalse(store.isShowingHome)
    }

    func testClosingLastTabLeadsToHome() throws {
        let store = TabsStore()
        try store.open(a)
        store.close(id: a.id)
        XCTAssertTrue(store.isShowingHome)
        XCTAssertTrue(store.isEmpty)
    }

    func testFolderGetsNoTab() throws {
        let store = TabsStore()
        try store.open(.folder("Folder"))
        XCTAssertTrue(store.isEmpty)
    }

    func testOpeningActivatesAndDoesNotDuplicate() throws {
        let store = try makeStore()
        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.activeID, c.id)

        try store.open(a)
        XCTAssertEqual(store.tabs.count, 3, "A node that is already open does not get a second tab")
        XCTAssertEqual(store.activeID, a.id)
    }

    func testSwitchingWrapsAround() throws {
        let store = try makeStore()
        try store.open(a)

        store.activateNext()
        XCTAssertEqual(store.activeID, b.id)

        store.activatePrevious()
        store.activatePrevious()
        XCTAssertEqual(store.activeID, c.id, "Before the first tab comes the last one")

        store.activateNext()
        XCTAssertEqual(store.activeID, a.id, "After the last tab comes the first one")

        store.activate(index: 1)
        XCTAssertEqual(store.activeID, b.id)
    }

    func testClosingLetsTheSuccessorMoveUp() throws {
        let store = try makeStore()
        store.activate(index: 1)

        store.close(id: b.id)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.activeID, c.id, "The successor moves into the freed slot")

        store.close(id: c.id)
        XCTAssertEqual(store.activeID, a.id, "At the end the previous tab remains")
    }

    func testCloseOthersAndCloseAll() throws {
        let store = try makeStore()

        store.closeOthers(than: b.id)
        XCTAssertEqual(store.tabs.map(\.id), [b.id])
        XCTAssertEqual(store.activeID, b.id)

        store.closeAll()
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.activeID)
    }

    func testRenamingAffectsTheTab() throws {
        let store = try makeStore()
        store.rename(id: b.id, to: "Bee")
        XCTAssertEqual(store.tab(id: b.id)?.title, "Bee")
    }

    func testPlaceholderWithoutFileGetsNoSession() throws {
        let store = TabsStore()
        try store.open(.pdf("No File"))
        XCTAssertNil(store.activeTab?.session)
    }
}
