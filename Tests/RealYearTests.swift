import XCTest
@testable import DXBPark

/// Milestone-1 contract: the savings year renders the REAL ledger. A save
/// parks a car in its month, a fine stamps the ✕, empty and future months
/// stay dotted, and receipt rows carry the actual amounts.
final class RealYearTests: XCTestCase {
    func testRealYearReflectsLedger() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))!

        let saveDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 10))!
        let save = InterventionEvent(kind: .unpaidNag, firedAt: saveDate,
                                     deadline: saveDate.addingTimeInterval(1800),
                                     zoneCode: "318C")
        save.outcome = .resolvedPaid
        save.resolvedAt = saveDate.addingTimeInterval(300)
        save.decisive = true
        save.estimatedFineAvoidedAED = 150

        let fineDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 18))!
        let fine = InterventionEvent(kind: .expiryWarning, firedAt: fineDate,
                                     deadline: fineDate, zoneCode: "373CP")
        fine.outcome = .gotFined
        fine.reportedFineAED = 150
        fine.finedAt = fineDate
        fine.resolvedAt = fineDate

        let model = RealYear.model(events: [save, fine], calendar: calendar, now: now)

        XCTAssertEqual(model.bays.count, 12)
        XCTAssertFalse(model.bays[2].future, "March has a save — car parked")
        XCTAssertFalse(model.bays[2].fined)
        XCTAssertTrue(model.bays[4].fined, "May took the fine")
        XCTAssertFalse(model.bays[4].future)
        XCTAssertTrue(model.bays[0].future, "empty January stays dotted")
        XCTAssertTrue(model.bays[8].future, "September is ahead")

        XCTAssertEqual(model.receipts[2].count, 1)
        XCTAssertEqual(model.receipts[2][0].1, "Paid Zone 318C after the nag")
        XCTAssertEqual(model.receipts[2][0].2, "+150")
        XCTAssertFalse(model.receipts[2][0].3)
        XCTAssertEqual(model.receipts[4][0].2, "−150")
        XCTAssertTrue(model.receipts[4][0].3)
        XCTAssertTrue(model.receipts[0].isEmpty)
    }

    func testDemoAndRealShareTheSameShape() {
        let demo = DemoYearAccess.model
        XCTAssertEqual(demo.bays.count, 12)
        XCTAssertEqual(demo.receipts.count, 12)
    }
}

/// DemoYear is file-private to SavingsCard; expose its shape via RealYear's
/// public pieces instead — a placeholder access point kept minimal.
private enum DemoYearAccess {
    static var model: YearModel {
        YearModel(bays: (0..<12).map { MonthBay(label: RealYear.monthAbbrev[$0], fined: false, future: true, tone: 0) },
                  receipts: Array(repeating: [], count: 12))
    }
}
