import XCTest
import SwiftData
@testable import DXBPark

/// Task 1 acceptance: a "save" appears only when a reminder demonstrably
/// preceded the corrective action, and one session yields at most one save.
final class InterventionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    /// Fixed base instant; tests add offsets. 07:45 Dubai on a paid morning.
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func t(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Session.self, Spot.self, InterventionEvent.self, ActivityEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private var allEvents: [InterventionEvent] {
        (try? context.fetch(FetchDescriptor<InterventionEvent>())) ?? []
    }
    private var decisiveEvents: [InterventionEvent] { allEvents.filter(\.decisive) }

    // MARK: - Pure decisive-window boundaries

    func testDecisiveWindowBoundaries() {
        // Morning reminder fired 07:45, enforcement starts 08:00 (deadline).
        let fired = t(0), deadline = t(15 * 60)
        // Paid 07:59 → decisive.
        XCTAssertTrue(InterventionResolver.isDecisive(firedAt: fired, deadline: deadline,
                                                      actionAt: t(14 * 60)))
        // Paid 08:01 (after enforcement began) → not a save.
        XCTAssertFalse(InterventionResolver.isDecisive(firedAt: fired, deadline: deadline,
                                                       actionAt: t(16 * 60)))
        // Paid exactly at the deadline → not a save (conservative).
        XCTAssertFalse(InterventionResolver.isDecisive(firedAt: fired, deadline: deadline,
                                                       actionAt: deadline))
        // Paid before the reminder even fired → the reminder can't have caused it.
        XCTAssertFalse(InterventionResolver.isDecisive(firedAt: fired, deadline: deadline,
                                                       actionAt: t(-60)))
    }

    // MARK: - Reminder fired → paid in window = decisive save

    func testNagFiredThenPaidInWindowIsDecisive() {
        let fireAt = t(5 * 60)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "444A", fireAt: fireAt,
            deadline: fireAt.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(0))

        let sessionID = UUID()
        InterventionLog.resolvePayment(zone: "444A", sessionID: sessionID,
                                       at: t(10 * 60), in: context)

        XCTAssertEqual(decisiveEvents.count, 1)
        let save = try! XCTUnwrap(decisiveEvents.first)
        XCTAssertEqual(save.outcome, .resolvedPaid)
        XCTAssertEqual(save.relatedSessionID, sessionID)
        XCTAssertEqual(save.estimatedFineAvoidedAED, ParkinRules.assumedFineAED)
    }

    // MARK: - Paid with no preceding reminder = not a save

    func testPaymentWithoutReminderIsNotASave() {
        InterventionLog.resolvePayment(zone: "444A", sessionID: UUID(), at: t(0), in: context)
        XCTAssertTrue(allEvents.isEmpty)
    }

    func testPaymentBeforeNagFiresIsNotASave() {
        // Nag scheduled for +5 min; user pays at +1 min — the normal flow.
        let fireAt = t(5 * 60)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "444A", fireAt: fireAt,
            deadline: fireAt.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(0))
        InterventionLog.resolvePayment(zone: "444A", sessionID: UUID(), at: t(60), in: context)
        XCTAssertTrue(decisiveEvents.isEmpty)

        // The cancel path then discards the never-fired nag entirely.
        InterventionLog.discardUnfired(kinds: [.unpaidNag], in: context, now: t(60))
        XCTAssertTrue(allEvents.isEmpty)
    }

    // MARK: - Expiry warning fired → lapsed with no extend = not a save

    func testExpiryWarningLapsedWithoutExtendIsNotASave() {
        let sessionID = UUID()
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "444A", fireAt: t(0), deadline: t(10 * 60),
            sessionID: sessionID, in: context, now: t(-60))

        InterventionLog.closePastDeadline(in: context, now: t(11 * 60))

        XCTAssertTrue(decisiveEvents.isEmpty)
        XCTAssertEqual(allEvents.first?.outcome, .dismissed)
    }

    func testExtendBeforeLapseIsDecisive() {
        let sessionID = UUID()
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "444A", fireAt: t(0), deadline: t(10 * 60),
            sessionID: sessionID, in: context, now: t(-60))

        InterventionLog.resolveExtend(sessionID: sessionID, at: t(5 * 60), in: context)

        XCTAssertEqual(decisiveEvents.count, 1)
        XCTAssertEqual(decisiveEvents.first?.outcome, .resolvedExtended)
    }

    // MARK: - Never double-count: at most one decisive save per session

    func testTwoRemindersOneSessionYieldAtMostOneSave() {
        // Morning reminder fired at 07:45 AND a nag fired at 08:05; user pays 08:10.
        InterventionLog.upsertScheduled(
            kind: .morningFreeToPaid, zone: "444A", fireAt: t(0), deadline: t(15 * 60),
            sessionID: nil, in: context, now: t(-60))
        let nagFire = t(20 * 60)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "444A", fireAt: nagFire,
            deadline: nagFire.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(-60))

        let sessionID = UUID()
        InterventionLog.resolvePayment(zone: "444A", sessionID: sessionID,
                                       at: t(25 * 60), in: context)

        XCTAssertEqual(decisiveEvents.count, 1)
        // The most recently fired reminder gets the credit.
        XCTAssertEqual(decisiveEvents.first?.kind, .unpaidNag)
        // Both are resolved either way.
        XCTAssertTrue(allEvents.allSatisfy { $0.outcome == .resolvedPaid })
    }

    func testExtendAfterEarlierSaveDoesNotDoubleCount() {
        let sessionID = UUID()
        // A fired nag already produced this session's save…
        let nagFire = t(0)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "444A", fireAt: nagFire,
            deadline: nagFire.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(-60))
        InterventionLog.resolvePayment(zone: "444A", sessionID: sessionID,
                                       at: t(60), in: context)
        XCTAssertEqual(decisiveEvents.count, 1)

        // …so a later fired expiry warning + extend resolves, but adds no save.
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "444A", fireAt: t(50 * 60), deadline: t(60 * 60),
            sessionID: sessionID, in: context, now: t(60))
        InterventionLog.resolveExtend(sessionID: sessionID, at: t(55 * 60), in: context)

        XCTAssertEqual(decisiveEvents.count, 1)
        XCTAssertEqual(allEvents.filter { $0.outcome == .resolvedExtended }.count, 1)
    }

    // MARK: - "I got fined" (Task 2): ground truth beats the estimate

    func testReportFineRemovesLikelySave() {
        let sessionID = UUID()
        let nagFire = t(0)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "444A", fireAt: nagFire,
            deadline: nagFire.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(-60))
        InterventionLog.resolvePayment(zone: "444A", sessionID: sessionID, at: t(60), in: context)
        XCTAssertEqual(SavingsStats.totals(in: context, now: t(60)).likelySaves, 1)

        InterventionLog.reportFine(sessionID: sessionID, amountAED: 200, at: t(3600), in: context)

        let totals = SavingsStats.totals(in: context, now: t(3600))
        XCTAssertEqual(totals.likelySaves, 0)
        XCTAssertEqual(totals.avoidedAED, 0)
        XCTAssertEqual(totals.finesReported, 1)
        XCTAssertEqual(totals.finesReportedAED, 200)
        XCTAssertEqual(allEvents.first?.outcome, .gotFined)
    }

    func testReportFineOnUncoveredSessionStillCounts() {
        let sessionID = UUID()
        InterventionLog.reportFine(sessionID: sessionID, amountAED: 150, at: t(0), in: context)
        let totals = SavingsStats.totals(in: context, now: t(0))
        XCTAssertEqual(totals.finesReported, 1)
        XCTAssertEqual(totals.likelySaves, 0)
    }

    func testFineOnSessionWithTwoEventsCountsOnce() {
        let sessionID = UUID()
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "444A", fireAt: t(0), deadline: t(600),
            sessionID: sessionID, in: context, now: t(-60))
        InterventionLog.resolveExtend(sessionID: sessionID, at: t(300), in: context)
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "444A", fireAt: t(3000), deadline: t(4200),
            sessionID: sessionID, in: context, now: t(300))

        InterventionLog.reportFine(sessionID: sessionID, amountAED: 150, at: t(5000), in: context)

        let totals = SavingsStats.totals(in: context, now: t(5000))
        XCTAssertEqual(totals.finesReported, 1)
        XCTAssertEqual(totals.finesReportedAED, 150)
        XCTAssertEqual(totals.likelySaves, 0)
    }

    // MARK: - Voided session (payment actually failed) revokes credit

    func testVoidSessionRevokesSaveAndClearsPending() {
        let sessionID = UUID()
        let nagFire = t(0)
        InterventionLog.upsertScheduled(
            kind: .unpaidNag, zone: "591B", fireAt: nagFire,
            deadline: nagFire.addingTimeInterval(ParkinRules.nagResolveWindow),
            sessionID: nil, in: context, now: t(-60))
        InterventionLog.resolvePayment(zone: "591B", sessionID: sessionID, at: t(60), in: context)
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: "591B", fireAt: t(50 * 60), deadline: t(60 * 60),
            sessionID: sessionID, in: context, now: t(60))
        XCTAssertEqual(SavingsStats.totals(in: context, now: t(60)).likelySaves, 1)

        InterventionLog.voidSession(sessionID: sessionID, in: context)

        let totals = SavingsStats.totals(in: context, now: t(60))
        XCTAssertEqual(totals.likelySaves, 0)
        XCTAssertEqual(totals.avoidedAED, 0)
        // Pending expiry warning for the voided session is gone entirely.
        XCTAssertTrue(InterventionLog.pendingEvents(in: context).isEmpty)
    }

    // MARK: - Savings card inputs (Task 3)

    func testEstimatedSpendCountsOnlyConfirmedSessions() {
        let paid = Session(plate: "A1", zoneCode: "318C", kind: .standard, durationHours: 2)
        paid.userConfirmedPaid = true          // 318C → ~AED 4/h × 2h = 8
        let unconfirmed = Session(plate: "A1", zoneCode: "318C", kind: .standard, durationHours: 3)
        XCTAssertEqual(SavingsStats.estimatedSpendAED(sessions: [paid, unconfirmed]), 8)
    }

    // MARK: - Activity log + monthly dashboard slices

    func testActivityLogDebouncesRepeatVisits() {
        ActivityLog.log(.quietArrival, label: "Home", in: context, now: t(0))
        ActivityLog.log(.quietArrival, label: "Home", in: context, now: t(60))          // same visit
        ActivityLog.log(.quietArrival, label: "Home", in: context,
                        now: t(ParkinRules.activityDebounce + 60))                      // new visit
        ActivityLog.log(.parkinOpened, in: context, now: t(60))                         // different kind
        let counts = ActivityLog.counts(in: context)
        XCTAssertEqual(counts[.quietArrival], 2)
        XCTAssertEqual(counts[.parkinOpened], 1)
    }

    func testMonthlySavesBucketsDecisiveOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!

        let save1 = InterventionEvent(kind: .unpaidNag, firedAt: june, deadline: june,
                                      zoneCode: "318C")
        save1.decisive = true; save1.estimatedFineAvoidedAED = 150; save1.resolvedAt = june
        let save2 = InterventionEvent(kind: .expiryWarning, firedAt: july, deadline: july,
                                      zoneCode: "382F")
        save2.decisive = true; save2.estimatedFineAvoidedAED = 150; save2.resolvedAt = july
        let noSave = InterventionEvent(kind: .unpaidNag, firedAt: july, deadline: july,
                                       zoneCode: "382F") // not decisive

        let slices = SavingsStats.monthlySaves(events: [save1, save2, noSave], months: 3,
                                               now: july, calendar: calendar)
        XCTAssertEqual(slices.count, 3)
        XCTAssertEqual(slices.map(\.saves), [0, 1, 1])       // May, June, July
        XCTAssertEqual(slices.last?.savedAED, 150)
        XCTAssertEqual(slices[1].savedAED, 150)
    }

    // MARK: - Demo seeder (test-build showcase data)

    func testDemoSeedCoversSixMonthsAllKindsAndOneFine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dubai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))!

        DemoData.seedSixMonths(in: context, now: now, calendar: calendar)

        let events = allEvents
        let slices = SavingsStats.monthlySaves(events: events, months: 6,
                                               now: now, calendar: calendar)
        XCTAssertEqual(slices.count, 6)
        // Completed months carry 6 saves each (30 = ~AED 4,500); the
        // in-progress month has sessions but no saves yet.
        XCTAssertTrue(slices.dropLast().allSatisfy { $0.saves == 6 })
        XCTAssertEqual(slices.map(\.saves).reduce(0, +), 30)
        XCTAssertEqual(SavingsStats.totals(in: context, now: now).avoidedAED, 4500)
        let kinds = Set(events.filter(\.decisive).map(\.kind))
        XCTAssertEqual(kinds, Set(InterventionKind.allCases), "all save types present")
        let totals = SavingsStats.totals(in: context, now: now)
        XCTAssertEqual(totals.finesReported, 1, "honesty row present")
        XCTAssertEqual(totals.likelySaves, slices.map(\.saves).reduce(0, +))
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertGreaterThanOrEqual(sessions.count, ParkinRules.recapMinimumSessions)
        XCTAssertFalse(ActivityLog.counts(in: context).isEmpty)
    }

    // MARK: - Rescheduling upserts, it never stacks duplicates

    func testReschedulingUpdatesUnfiredEventInPlace() {
        for minute in [0.0, 1, 2] {
            let fireAt = t(minute * 60 + ParkinRules.nagDelay)
            InterventionLog.upsertScheduled(
                kind: .unpaidNag, zone: "444A", fireAt: fireAt,
                deadline: fireAt.addingTimeInterval(ParkinRules.nagResolveWindow),
                sessionID: nil, in: context, now: t(minute * 60))
        }
        XCTAssertEqual(allEvents.count, 1)
        XCTAssertEqual(allEvents.first?.firedAt, t(2 * 60 + ParkinRules.nagDelay))
    }
}
