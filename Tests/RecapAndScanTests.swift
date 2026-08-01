import XCTest
@testable import DXBPark

final class RecapAndScanTests: XCTestCase {

    // MARK: - Recap stats (Task 4): every figure from confirmed data only

    private func session(zone: String, hours: Int, confirmed: Bool = true,
                         startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Session {
        let session = Session(plate: "A1", zoneCode: zone, kind: .standard,
                              durationHours: hours, startedAt: startedAt)
        session.userConfirmedPaid = confirmed
        return session
    }

    func testRecapCountsOnlyConfirmedSessions() {
        let sessions = [
            session(zone: "318C", hours: 2),
            session(zone: "318C", hours: 1),
            session(zone: "382F", hours: 4),
            session(zone: "444A", hours: 3, confirmed: false), // never confirmed
        ]
        let stats = RecapStats.compute(sessions: sessions, totals: SavingsTotals())
        XCTAssertEqual(stats.timesParked, 3)
        XCTAssertEqual(stats.topZone, "318C")
        XCTAssertEqual(stats.topZoneCount, 2)
        XCTAssertEqual(stats.longestSessionHours, 4)
    }

    func testRecapFinesDodgedEqualsLedgerTotals() {
        // Acceptance: the fines-dodged figure IS the decisive ledger total.
        var totals = SavingsTotals()
        totals.likelySaves = 3
        totals.avoidedAED = 450
        let stats = RecapStats.compute(sessions: [], totals: totals)
        XCTAssertEqual(stats.likelySaves, 3)
        XCTAssertEqual(stats.savedAED, 450)
    }

    func testRecapBusiestWeekdayIsDeterministic() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        calendar.locale = Locale(identifier: "en_US")
        // 2026-07-20 is a Monday; 07-21 a Tuesday.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 10))!
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 10))!
        let sessions = [
            session(zone: "318C", hours: 1, startedAt: monday),
            session(zone: "318C", hours: 1, startedAt: monday),
            session(zone: "318C", hours: 1, startedAt: tuesday),
        ]
        let stats = RecapStats.compute(sessions: sessions, totals: SavingsTotals(),
                                       calendar: calendar)
        XCTAssertEqual(stats.busiestWeekday, "Monday")
    }

    // MARK: - Types-of-savings breakdown

    func testSavesByKindCountsDecisiveOnly() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let nag = InterventionEvent(kind: .unpaidNag, firedAt: base, deadline: base, zoneCode: "318C")
        nag.decisive = true; nag.estimatedFineAvoidedAED = 150
        let morning = InterventionEvent(kind: .morningFreeToPaid, firedAt: base, deadline: base, zoneCode: "318C")
        morning.decisive = true; morning.estimatedFineAvoidedAED = 150
        let nag2 = InterventionEvent(kind: .unpaidNag, firedAt: base, deadline: base, zoneCode: "382F")
        nag2.decisive = true; nag2.estimatedFineAvoidedAED = 150
        let notDecisive = InterventionEvent(kind: .expiryWarning, firedAt: base, deadline: base, zoneCode: "382F")

        let breakdown = SavingsStats.savesByKind(events: [nag, morning, nag2, notDecisive])
        XCTAssertEqual(breakdown.count, 2) // expiry had no decisive save → omitted
        XCTAssertEqual(breakdown.first { $0.kind == .unpaidNag }?.saves, 2)
        XCTAssertEqual(breakdown.first { $0.kind == .unpaidNag }?.savedAED, 300)
        XCTAssertEqual(breakdown.first { $0.kind == .morningFreeToPaid }?.saves, 1)
    }

    // MARK: - Zone-code extraction from scanned sign text (Task 5)

    func testExtractsZoneCodeFromSignText() {
        let strings = ["PARKIN", "ZONE 382F", "8:00 AM - 10:00 PM", "AED 4 / HR"]
        XCTAssertEqual(ZoneScan.candidates(in: strings), ["382F"])
    }

    func testExtractionHandlesNoiseAndDuplicates() {
        let strings = ["zone 318c", "318C", "SEND 7275", "CC41190", "2026", "318W"]
        // 7275 (4 digits, no letter), CC41190 and 2026 don't match; 318C deduped.
        XCTAssertEqual(ZoneScan.candidates(in: strings), ["318C", "318W"])
    }

    func testExtractionIgnoresPlainNumbersAndShortCodes() {
        XCTAssertTrue(ZoneScan.candidates(in: ["444", "12A", "AED 10", "10PM"]).isEmpty)
    }
}
