import XCTest
@testable import DXBPark

/// The tier contract: free = protection + 7 days; signed-in (or the owner's
/// demo profile) = memory, 90 days, the automation nudge.
final class TierTests: XCTestCase {
    private var savedUserID: String?
    private var savedPresenter: Bool = false

    override func setUp() {
        super.setUp()
        savedUserID = UserDefaults.standard.string(forKey: "appleUserID")
        savedPresenter = UserDefaults.standard.bool(forKey: "presenterMode")
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.set(false, forKey: "presenterMode")
    }

    override func tearDown() {
        if let savedUserID {
            UserDefaults.standard.set(savedUserID, forKey: "appleUserID")
        } else {
            UserDefaults.standard.removeObject(forKey: "appleUserID")
        }
        UserDefaults.standard.set(savedPresenter, forKey: "presenterMode")
        super.tearDown()
    }

    func testFreeTierGates() {
        XCTAssertFalse(Tier.isEntitled)
        XCTAssertFalse(Tier.remembersZoneSpots)
        XCTAssertFalse(Tier.autoNudgeEnabled)
        let calendar = Calendar.current
        let now = Date.now
        let cutoff = Tier.historyCutoff(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: cutoff, to: now).day
        XCTAssertEqual(days, Tier.freeHistoryDays)
    }

    func testSignedInUnlocksMemory() {
        UserDefaults.standard.set("001234.fake.5678", forKey: "appleUserID")
        XCTAssertTrue(Tier.isEntitled)
        XCTAssertTrue(Tier.remembersZoneSpots)
        XCTAssertTrue(Tier.autoNudgeEnabled)
        let calendar = Calendar.current
        let now = Date.now
        let cutoff = Tier.historyCutoff(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: cutoff, to: now).day
        XCTAssertEqual(days, Tier.signedInHistoryDays)
    }

    func testPresenterProfileCountsAsEntitled() {
        UserDefaults.standard.set(true, forKey: "presenterMode")
        XCTAssertTrue(Tier.isEntitled, "the owner's demo device must look complete")
    }
}
