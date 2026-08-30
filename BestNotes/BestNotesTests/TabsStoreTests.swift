//
//  TabsStoreTests.swift
//  BestNotesTests
//

import XCTest
@testable import BestNotes

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

    func testOrdnerBekommtKeinenTab() throws {
        let store = TabsStore()
        try store.open(.folder("Ordner"))
        XCTAssertTrue(store.isEmpty)
    }

    func testOeffnenAktiviertUndDupliziertNicht() throws {
        let store = try makeStore()
        XCTAssertEqual(store.tabs.count, 3)
        XCTAssertEqual(store.activeID, c.id)

        try store.open(a)
        XCTAssertEqual(store.tabs.count, 3, "Ein bereits offener Knoten bekommt keinen zweiten Tab")
        XCTAssertEqual(store.activeID, a.id)
    }

    func testWechselnLaeuftUmDieRaender() throws {
        let store = try makeStore()
        try store.open(a)

        store.activateNext()
        XCTAssertEqual(store.activeID, b.id)

        store.activatePrevious()
        store.activatePrevious()
        XCTAssertEqual(store.activeID, c.id, "Vor dem ersten Tab kommt der letzte")

        store.activateNext()
        XCTAssertEqual(store.activeID, a.id, "Hinter dem letzten Tab kommt der erste")

        store.activate(index: 1)
        XCTAssertEqual(store.activeID, b.id)
    }

    func testSchliessenLaesstDenNachfolgerNachruecken() throws {
        let store = try makeStore()
        store.activate(index: 1)

        store.close(id: b.id)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.activeID, c.id, "An die frei gewordene Stelle rueckt der Nachfolger")

        store.close(id: c.id)
        XCTAssertEqual(store.activeID, a.id, "Am Ende bleibt der vorherige Tab")
    }

    func testAndereUndAlleSchliessen() throws {
        let store = try makeStore()

        store.closeOthers(than: b.id)
        XCTAssertEqual(store.tabs.map(\.id), [b.id])
        XCTAssertEqual(store.activeID, b.id)

        store.closeAll()
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.activeID)
    }

    func testUmbenennenWirktAufDenTab() throws {
        let store = try makeStore()
        store.rename(id: b.id, to: "Bee")
        XCTAssertEqual(store.tab(id: b.id)?.title, "Bee")
    }

    func testPlatzhalterOhneDateiBekommtKeineSitzung() throws {
        let store = TabsStore()
        try store.open(.pdf("Ohne Datei"))
        XCTAssertNil(store.activeTab?.session)
    }
}
