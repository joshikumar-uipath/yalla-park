import XCTest
import CoreLocation
@testable import DXBPark

/// Phase 2+3 contracts: the four non-Dubai operators' SMS formats, their
/// enforcement calendars (Sharjah's 2026 unification, Ajman's split windows),
/// and the coarse emirate geofences.
final class RegionTests: XCTestCase {
    private let plate = PlateProfile(emirate: .dubai, letters: "BB", number: "60925")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    // MARK: - SMS formats

    func testMawaqifBodyFusedPlateWithTier() {
        XCTAssertEqual(ParkingOperator.mawaqif.smsBody(plate: plate, zone: "S", hours: 2),
                       "DXBBB 60925 S 2")
        XCTAssertEqual(ParkingOperator.mawaqif.smsBody(plate: plate, zone: "p", hours: 1),
                       "DXBBB 60925 P 1")
        // Unknown tier falls back to Standard, never an invalid literal.
        XCTAssertEqual(ParkingOperator.mawaqif.smsBody(plate: plate, zone: "", hours: 1),
                       "DXBBB 60925 S 1")
    }

    func testSharjahBodyDropsPlateLetters() {
        XCTAssertEqual(ParkingOperator.sharjah.smsBody(plate: plate, zone: "", hours: 2),
                       "DXB 60925 2")
    }

    func testAjmanAndFujairahBodiesFullySpaced() {
        XCTAssertEqual(ParkingOperator.ajman.smsBody(plate: plate, zone: "", hours: 1),
                       "DXB BB 60925 1")
        XCTAssertEqual(ParkingOperator.fujairah.smsBody(plate: plate, zone: "", hours: 2),
                       "DXB BB 60925 2")
        // Letterless plates collapse cleanly — no double space.
        let letterless = PlateProfile(emirate: .sharjah, letters: "", number: "12345")
        XCTAssertEqual(ParkingOperator.ajman.smsBody(plate: letterless, zone: "", hours: 1),
                       "SHJ 12345 1")
    }

    func testSMSNumbersAndExtendMethods() {
        XCTAssertEqual(ParkingOperator.mawaqif.smsNumber, "3009")
        XCTAssertEqual(ParkingOperator.fujairah.smsNumber, "3009")
        XCTAssertEqual(ParkingOperator.sharjah.smsNumber, "5566")
        XCTAssertEqual(ParkingOperator.ajman.smsNumber, "5155")
        XCTAssertEqual(ParkingOperator.mawaqif.extendMethod, .reply("E"))
        XCTAssertEqual(ParkingOperator.fujairah.extendMethod, .reply("E"))
        XCTAssertEqual(ParkingOperator.ajman.extendMethod, .reply("Y"))
        XCTAssertEqual(ParkingOperator.sharjah.extendMethod, .resendPayment)
        XCTAssertEqual(ParkingOperator.ajman.maxHoursPerSMS, 1)
        XCTAssertEqual(ParkingOperator.sharjah.maxHoursPerSMS, 5)
    }

    // MARK: - Calendars

    func testSharjahChargesDailyToMidnightSinceJuly2026() {
        // Friday 2026-08-07 was a Friday? 2026-08-07 is a Friday. Sharjah
        // charges Fridays since the unification.
        let friday = date(2026, 8, 7, 21)
        let verdictFriday = RegionRules.verdict(for: .sharjah, kind: .standard, at: friday)
        XCTAssertTrue(verdictFriday.paymentRequired, "Sharjah charges Fridays now")
        // 23:30 still charging (until midnight); 00:30 free.
        XCTAssertTrue(RegionRules.verdict(for: .sharjah, kind: .standard,
                                          at: date(2026, 8, 5, 23, 30)).paymentRequired)
        let smallHours = RegionRules.verdict(for: .sharjah, kind: .standard,
                                             at: date(2026, 8, 6, 0, 30))
        XCTAssertFalse(smallHours.paymentRequired)
        XCTAssertEqual(smallHours.nextChange, date(2026, 8, 6, 8))
    }

    func testAjmanSplitWindowsAndFreeFriday() {
        // Wednesday mid-morning: charged.
        XCTAssertTrue(RegionRules.verdict(for: .ajman, kind: .standard,
                                          at: date(2026, 8, 5, 10)).paymentRequired)
        // Wednesday 14:00 sits between the windows: free until 17:00.
        let gap = RegionRules.verdict(for: .ajman, kind: .standard, at: date(2026, 8, 5, 14))
        XCTAssertFalse(gap.paymentRequired)
        XCTAssertEqual(gap.nextChange, date(2026, 8, 5, 17))
        // Evening window charges until 22:00.
        let evening = RegionRules.verdict(for: .ajman, kind: .standard, at: date(2026, 8, 5, 18))
        XCTAssertTrue(evening.paymentRequired)
        XCTAssertEqual(evening.nextChange, date(2026, 8, 5, 22))
        // Friday is free all day; next charge Saturday 08:00.
        let friday = RegionRules.verdict(for: .ajman, kind: .standard, at: date(2026, 8, 7, 10))
        XCTAssertFalse(friday.paymentRequired)
        XCTAssertEqual(friday.nextChange, date(2026, 8, 8, 8))
    }

    func testMawaqifSundayFreeAndMidnightClose() {
        // Sunday 2026-08-09: free.
        XCTAssertFalse(RegionRules.verdict(for: .mawaqif, kind: .standard,
                                           at: date(2026, 8, 9, 11)).paymentRequired)
        // Monday 23:00: still charging (Mawaqif runs to midnight).
        XCTAssertTrue(RegionRules.verdict(for: .mawaqif, kind: .standard,
                                          at: date(2026, 8, 10, 23)).paymentRequired)
    }

    func testMaxPayableHoursRespectsWindowEnd() {
        // Ajman 11:00 → morning window ends 13:00 → 2 hours payable.
        XCTAssertEqual(RegionRules.maxPayableHours(for: .ajman, kind: .standard,
                                                   at: date(2026, 8, 5, 11)), 2)
        // Sharjah 22:00 → midnight → 2 hours.
        XCTAssertEqual(RegionRules.maxPayableHours(for: .sharjah, kind: .standard,
                                                   at: date(2026, 8, 5, 22)), 2)
    }

    func testFreeKindShortCircuitsEverywhere() {
        XCTAssertFalse(RegionRules.verdict(for: .sharjah, kind: .free,
                                           at: date(2026, 8, 5, 12)).paymentRequired)
    }

    // MARK: - Emirate geofences

    private func operatorAt(_ lat: Double, _ lon: Double) -> ParkingOperator? {
        EmirateLocator.parkingOperator(at: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    func testEmirateGeofences() {
        XCTAssertEqual(operatorAt(24.47, 54.36), .mawaqif, "Abu Dhabi Corniche")
        XCTAssertEqual(operatorAt(24.22, 55.76), .mawaqif, "Al Ain")
        XCTAssertEqual(operatorAt(25.325, 55.385), .sharjah, "Al Majaz, Sharjah")
        XCTAssertEqual(operatorAt(25.412, 55.435), .ajman, "Ajman Corniche")
        XCTAssertEqual(operatorAt(25.13, 56.34), .fujairah, "Fujairah city")
        XCTAssertEqual(operatorAt(25.34, 56.35), .sharjah, "Khor Fakkan is Sharjah's")
        XCTAssertNotNil(EmirateLocator.note(at: CLLocationCoordinate2D(latitude: 25.34, longitude: 56.35)),
                        "exclaves explain themselves")
        XCTAssertNil(EmirateLocator.note(at: CLLocationCoordinate2D(latitude: 25.325, longitude: 55.385)),
                     "Sharjah city needs no explanation")
        XCTAssertEqual(operatorAt(25.02, 56.35), .sharjah, "Kalba is Sharjah's")
        XCTAssertNil(operatorAt(25.2048, 55.2708), "Downtown Dubai — community polygons handle Dubai")
        XCTAssertNil(operatorAt(24.9, 55.0), "Open desert")
    }

    // MARK: - Regional fines (savings ledger)

    func testRegionalFineAssumptions() {
        XCTAssertEqual(ParkingOperator.parkin.assumedFineAED, 150)
        XCTAssertEqual(ParkingOperator.mawaqif.assumedFineAED, 200)
        XCTAssertEqual(ParkingOperator.sharjah.assumedFineAED, 100)
    }

    func testDubaiVerdictDelegatesUnchanged() {
        let monday = date(2026, 8, 10, 10)
        XCTAssertEqual(RegionRules.verdict(for: .parkin, kind: .standard, at: monday),
                       ParkinRules.verdict(kind: .standard, at: monday))
        let sunday = date(2026, 8, 9, 10)
        XCTAssertEqual(RegionRules.verdict(for: .parkonic, kind: .standard, at: sunday),
                       ParkinRules.verdict(kind: .standard, at: sunday))
    }
}
