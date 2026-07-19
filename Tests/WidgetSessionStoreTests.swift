import XCTest
@testable import DXBPark

/// The widget's view of the session must appear on save, survive an extend,
/// vanish on clear, and never show an expired session.
final class WidgetSessionStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WidgetSessionStore.clear()
    }

    override func tearDown() {
        WidgetSessionStore.clear()
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        WidgetSessionStore.save(zoneCode: "444A", plate: "A44821",
                                startedAt: start, expiresAt: start.addingTimeInterval(3600))
        let loaded = WidgetSessionStore.load(at: start.addingTimeInterval(60))
        XCTAssertEqual(loaded?.zoneCode, "444A")
        XCTAssertEqual(loaded?.plate, "A44821")
        XCTAssertEqual(loaded?.expiresAt, start.addingTimeInterval(3600))
    }

    func testExpiredSessionLoadsAsNil() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        WidgetSessionStore.save(zoneCode: "444A", plate: "A44821",
                                startedAt: start, expiresAt: start.addingTimeInterval(3600))
        XCTAssertNil(WidgetSessionStore.load(at: start.addingTimeInterval(3600)))
        XCTAssertNil(WidgetSessionStore.load(at: start.addingTimeInterval(7200)))
    }

    func testUpdateMovesDatesKeepsZoneAndPlate() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        WidgetSessionStore.save(zoneCode: "365B", plate: "K1207",
                                startedAt: start, expiresAt: start.addingTimeInterval(3600))
        WidgetSessionStore.update(startedAt: start, expiresAt: start.addingTimeInterval(7200))
        let loaded = WidgetSessionStore.load(at: start.addingTimeInterval(5400))
        XCTAssertEqual(loaded?.zoneCode, "365B")
        XCTAssertEqual(loaded?.plate, "K1207")
        XCTAssertEqual(loaded?.expiresAt, start.addingTimeInterval(7200))
    }

    func testClearRemovesSession() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        WidgetSessionStore.save(zoneCode: "444A", plate: "A44821",
                                startedAt: start, expiresAt: start.addingTimeInterval(3600))
        WidgetSessionStore.clear()
        XCTAssertNil(WidgetSessionStore.load(at: start))
    }

    func testUpdateWithoutStoredSessionIsNoOp() {
        WidgetSessionStore.update(startedAt: .distantPast, expiresAt: .distantFuture)
        XCTAssertNil(WidgetSessionStore.load(at: .distantPast))
    }
}
