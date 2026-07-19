import XCTest
@testable import DXBPark

/// Boundary tests for the free/paid decision engine (§15: "get the free/paid math
/// exactly right — write unit tests for the boundaries").
/// All dates are Asia/Dubai. July 2026: Mon 20th … Sat 25th, Sun 19th/26th.
final class ParkinRulesTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Daily window boundaries (standard zone)

    func testMonday0759IsFree() {
        XCTAssertFalse(ParkinRules.verdict(kind: .standard, at: date(2026, 7, 20, 7, 59)).paymentRequired)
    }

    func testMonday0800IsPaid() {
        XCTAssertTrue(ParkinRules.verdict(kind: .standard, at: date(2026, 7, 20, 8, 0)).paymentRequired)
    }

    func testMonday2159IsPaid() {
        XCTAssertTrue(ParkinRules.verdict(kind: .standard, at: date(2026, 7, 20, 21, 59)).paymentRequired)
    }

    func testMonday2200IsFree() {
        XCTAssertFalse(ParkinRules.verdict(kind: .standard, at: date(2026, 7, 20, 22, 0)).paymentRequired)
    }

    // MARK: - Weekly boundaries

    func testSundayNoonIsFreeInStandardZone() {
        let verdict = ParkinRules.verdict(kind: .standard, at: date(2026, 7, 19, 12, 0))
        XCTAssertFalse(verdict.paymentRequired)
        // Next paid start must be Monday 08:00, not later today.
        XCTAssertEqual(verdict.nextChange, date(2026, 7, 20, 8, 0))
    }

    func testSaturdayNoonIsPaidInStandardZone() {
        XCTAssertTrue(ParkinRules.verdict(kind: .standard, at: date(2026, 7, 25, 12, 0)).paymentRequired)
    }

    func testSaturdayNightRollsOverSundayToMonday() {
        // Parked Saturday 23:00 — free overnight, free all Sunday, paid Monday 08:00.
        let next = ParkinRules.nextPaidStart(kind: .standard, after: date(2026, 7, 25, 23, 0))
        XCTAssertEqual(next, date(2026, 7, 27, 8, 0))
    }

    func testSundayIsPaidInPremiumZone() {
        XCTAssertTrue(ParkinRules.verdict(kind: .premium, at: date(2026, 7, 19, 12, 0)).paymentRequired)
    }

    // MARK: - Public holidays

    func testNationalDayIsFreeInStandardZone() {
        // Dec 2 2026 is a Wednesday and a public holiday.
        XCTAssertFalse(ParkinRules.verdict(kind: .standard, at: date(2026, 12, 2, 12, 0)).paymentRequired)
    }

    func testHolidayRunSkipsToFirstChargedDay() {
        // Dec 2 + Dec 3 are holidays; Dec 4 is a Friday (charged).
        let next = ParkinRules.nextPaidStart(kind: .standard, after: date(2026, 12, 2, 12, 0))
        XCTAssertEqual(next, date(2026, 12, 4, 8, 0))
    }

    func testHolidayIsStillPaidInPremiumZone() {
        XCTAssertTrue(ParkinRules.verdict(kind: .premium, at: date(2026, 12, 2, 12, 0)).paymentRequired)
    }

    // MARK: - Multi-storey

    func testMultistoreyIsAlwaysPaidWithNoNextChange() {
        let verdict = ParkinRules.verdict(kind: .multistorey, at: date(2026, 7, 19, 3, 0))
        XCTAssertTrue(verdict.paymentRequired)
        XCTAssertNil(verdict.nextChange)
    }

    // MARK: - Duration capping

    func testMaxHoursNearClosingIsOne() {
        XCTAssertEqual(ParkinRules.maxPayableHours(kind: .standard, at: date(2026, 7, 20, 20, 30)), 1)
    }

    func testMaxHoursEarlyEveningIsThree() {
        XCTAssertEqual(ParkinRules.maxPayableHours(kind: .standard, at: date(2026, 7, 20, 19, 0)), 3)
    }

    // MARK: - SMS body

    func testSmsBodyFormat() {
        XCTAssertEqual(ParkinRules.smsBody(plate: "a 44821", zone: "444a", hours: 2), "A44821 444A 2")
    }
}
