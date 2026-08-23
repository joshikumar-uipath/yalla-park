import Foundation
import SwiftData

/// Test-build-only: fills six months of realistic history so the savings
/// dashboard and recap can be demoed. Deterministic (no randomness), spread
/// across zones, payment methods, all three save kinds, activity kinds, and
/// one reported fine — because an honest demo shows the honesty machinery too.
enum DemoData {
    static let zones = ["318C", "382F", "248W", "334B", "365A", "112D"]

    /// True in Xcode debug runs and TestFlight installs; false on the App
    /// Store — demo behavior disappears automatically at public release.
    static var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    static func seedSixMonths(in context: ModelContext, now: Date = .now,
                              calendar: Calendar = .current) {
        guard let currentMonth = calendar.dateInterval(of: .month, for: now)?.start
        else { return }
        var zoneIndex = 0

        for offset in -5...0 {
            guard let month = calendar.date(byAdding: .month, value: offset,
                                            to: currentMonth) else { continue }
            let sessionCount = 8
            // 8 saves in each of the 5 completed months = 40 = ~AED 6,000;
            // the in-progress month gets sessions but no saves yet.
            let saveTarget = offset < 0 ? 8 : 0

            for i in 0..<sessionCount {
                // Day spacing must keep all sessions inside the month even
                // in February (max day 1 + 7*3 = 22).
                guard let start = calendar.date(
                    byAdding: DateComponents(day: 1 + i * 3, hour: 9 + (i % 8)), to: month),
                    start < now else { continue }
                let zone = zones[zoneIndex % zones.count]
                zoneIndex += 1

                let session = Session(plate: "CC41190", zoneCode: zone,
                                      kind: .standard, durationHours: 1 + (i % 3),
                                      startedAt: start)
                session.paymentAttempted = true
                session.userConfirmedPaid = true
                session.paidViaParkinApp = (i % 3 == 0)
                context.insert(session)

                if i < saveTarget {
                    let kinds = InterventionKind.allCases
                    let kind = kinds[(offset + 5 + i) % kinds.count]
                    let fired = start.addingTimeInterval(
                        kind == .expiryWarning ? 50 * 60 : 5 * 60)
                    let event = InterventionEvent(
                        kind: kind, firedAt: fired,
                        deadline: fired.addingTimeInterval(ParkinRules.nagResolveWindow),
                        zoneCode: zone, relatedSessionID: session.id)
                    event.outcome = kind == .expiryWarning ? .resolvedExtended : .resolvedPaid
                    event.resolvedAt = fired.addingTimeInterval(7 * 60)
                    event.decisive = true
                    event.estimatedFineAvoidedAED = ParkinRules.assumedFineAED
                    context.insert(event)
                }
            }

            // One real fine mid-window — the ledger never hides misses.
            if offset == -3,
               let at = calendar.date(byAdding: DateComponents(day: 20, hour: 18),
                                      to: month), at < now {
                let fined = InterventionEvent(kind: .expiryWarning, firedAt: at,
                                              deadline: at, zoneCode: "382F")
                fined.outcome = .gotFined
                fined.reportedFineAED = ParkinRules.assumedFineAED
                fined.finedAt = at
                fined.resolvedAt = at
                context.insert(fined)
            }

            // Non-monetary activity: quiet arrivals, hand-offs, dismissals.
            let activity: [(ActivityKind, Int, String)] = [
                (.quietArrival, 8, "Home"), (.parkinOpened, 2, ""),
                (.smsPayStarted, 2, ""), (.notParkingDismissed, 1, ""),
                (.freeArrival, 2, "Jebel Ali"),
            ]
            for (kind, count, label) in activity {
                for j in 0..<count {
                    if let at = calendar.date(
                        byAdding: DateComponents(day: 1 + j * 3, hour: 8 + j), to: month),
                       at < now {
                        context.insert(ActivityEvent(kind: kind, at: at, label: label))
                    }
                }
            }
        }
    }

    /// Wipe every stats-bearing record (sessions, ledger, activity). Spots and
    /// settings survive.
    static func clearStats(in context: ModelContext) {
        try? context.delete(model: InterventionEvent.self)
        try? context.delete(model: ActivityEvent.self)
        try? context.delete(model: Session.self)
    }
}
