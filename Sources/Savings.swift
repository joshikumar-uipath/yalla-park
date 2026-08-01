import Foundation
import SwiftData

/// The honest "fines likely avoided" model (build-tasks Task 1).
///
/// A save only counts when a reminder plausibly *caused* the fix: the
/// corrective action landed after the reminder fired and before its deadline —
/// the last moment the intervention could still have prevented a fine. Paying
/// normally, with no fired reminder preceding it, is never a save. Copy built
/// on this data must always say "likely" / "about" — never certainty.

enum InterventionKind: String, Codable {
    case morningFreeToPaid  // layer 3: free now, enforcement starts soon
    case unpaidNag          // layer 4a: dismissed a paid zone without paying
    case expiryWarning      // layer 4b: session about to lapse
}

enum InterventionOutcome: String, Codable {
    case pending            // scheduled or fired, not yet acted on
    case resolvedPaid       // a confirmed payment followed
    case resolvedExtended   // an extension followed
    case dismissed          // deadline passed with no corrective action
    case gotFined           // user reported a real fine (Task 2)
}

@Model
final class InterventionEvent {
    var id: UUID
    var kindRaw: String
    /// When the notification fires (its scheduled time — iOS never tells the app
    /// the actual delivery moment, so events are logged at *schedule* time and
    /// count as fired once this passes; cancelled-before-fire events are deleted).
    var firedAt: Date
    /// Last moment the intervention could still have prevented the fine
    /// (morning → enforcement start; nag → firedAt + window; expiry → lapse).
    var deadline: Date
    var zoneCode: String
    var relatedSessionID: UUID?
    var outcomeRaw: String
    var resolvedAt: Date?
    /// True only when the reminder demonstrably preceded the corrective action.
    var decisive: Bool
    /// 0 unless decisive.
    var estimatedFineAvoidedAED: Decimal
    /// Set when the user reports a real fine (Task 2) — ground truth that
    /// overrides any "likely avoided" credit.
    var reportedFineAED: Decimal?
    var finedAt: Date?

    var kind: InterventionKind { InterventionKind(rawValue: kindRaw) ?? .unpaidNag }
    var outcome: InterventionOutcome {
        get { InterventionOutcome(rawValue: outcomeRaw) ?? .pending }
        set { outcomeRaw = newValue.rawValue }
    }

    init(kind: InterventionKind, firedAt: Date, deadline: Date,
         zoneCode: String, relatedSessionID: UUID? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.firedAt = firedAt
        self.deadline = deadline
        self.zoneCode = zoneCode
        self.relatedSessionID = relatedSessionID
        self.outcomeRaw = InterventionOutcome.pending.rawValue
        self.resolvedAt = nil
        self.decisive = false
        self.estimatedFineAvoidedAED = 0
        self.reportedFineAED = nil
        self.finedAt = nil
    }
}

// MARK: - Activity log (dashboard requested from field use)

/// Moments the app earned its keep that aren't reminder-caused saves: hand-offs
/// to Parkin, SMS pays, false-trigger dismissals, quiet arrivals at Home/Office
/// or free spots. Counted as ACTIVITY on the dashboard — never as money; AED
/// figures come exclusively from decisive InterventionEvents.
enum ActivityKind: String, Codable, CaseIterable {
    case parkinOpened       // tapped "Pay in the Parkin app"
    case smsPayStarted      // opened the SMS composer to pay
    case notParkingDismissed // "I'm not parking here" (false trigger caught)
    case quietArrival       // arrived at Home/Office — app stayed silent
    case freeArrival        // arrived at a user-marked free spot
}

@Model
final class ActivityEvent {
    var id: UUID
    var kindRaw: String
    var at: Date
    var label: String

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .quietArrival }

    init(kind: ActivityKind, at: Date = .now, label: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.at = at
        self.label = label
    }
}

enum ActivityLog {
    /// Log once per "visit": repeated pipeline runs at the same place within
    /// the debounce window collapse into one event.
    static func log(_ kind: ActivityKind, label: String = "",
                    in context: ModelContext, now: Date = .now) {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.at, order: .reverse)])
        descriptor.fetchLimit = 1
        if let last = (try? context.fetch(descriptor))?.first,
           now.timeIntervalSince(last.at) < ParkinRules.activityDebounce {
            return
        }
        context.insert(ActivityEvent(kind: kind, at: now, label: label))
    }

    static func counts(in context: ModelContext) -> [ActivityKind: Int] {
        let events = (try? context.fetch(FetchDescriptor<ActivityEvent>())) ?? []
        return Dictionary(grouping: events, by: \.kind).mapValues(\.count)
    }
}

/// One month of the honest ledger, for the dashboard chart.
struct MonthlySlice: Equatable {
    var month: Date        // first instant of the month
    var saves: Int
    var savedAED: Decimal
}

extension SavingsStats {
    /// Decisive saves bucketed by month (oldest → newest), covering the last
    /// `months` months including the current one. Empty months included so the
    /// chart reads as a timeline, not a lineup of survivors.
    static func monthlySaves(events: [InterventionEvent], months: Int = 6,
                             now: Date = .now,
                             calendar: Calendar = .current) -> [MonthlySlice] {
        guard months > 0,
              let currentMonth = calendar.dateInterval(of: .month, for: now)?.start
        else { return [] }
        var slices: [MonthlySlice] = []
        for offset in stride(from: -(months - 1), through: 0, by: 1) {
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth)
            else { continue }
            slices.append(MonthlySlice(month: month, saves: 0, savedAED: 0))
        }
        for event in events where event.decisive {
            let anchor = event.resolvedAt ?? event.firedAt
            guard let month = calendar.dateInterval(of: .month, for: anchor)?.start,
                  let index = slices.firstIndex(where: { $0.month == month }) else { continue }
            slices[index].saves += 1
            slices[index].savedAED += event.estimatedFineAvoidedAED
        }
        return slices
    }
}

/// Rollup for the stats line and (Task 3) the savings card — every number
/// traces to individual events, no global multipliers.
struct SavingsTotals: Equatable {
    var remindersFired = 0
    var likelySaves = 0
    var avoidedAED = Decimal(0)
    var finesReported = 0
    var finesReportedAED = Decimal(0)
}

enum SavingsStats {
    static func totals(in context: ModelContext, now: Date = .now) -> SavingsTotals {
        let events = (try? context.fetch(FetchDescriptor<InterventionEvent>())) ?? []
        var totals = SavingsTotals()
        var finedSessions = Set<UUID>()
        for event in events {
            if event.firedAt <= now { totals.remindersFired += 1 }
            if event.decisive {
                totals.likelySaves += 1
                totals.avoidedAED += event.estimatedFineAvoidedAED
            }
            // A session's fine is reported onto every one of its events — count once.
            if event.outcome == .gotFined, let amount = event.reportedFineAED,
               finedSessions.insert(event.relatedSessionID ?? event.id).inserted {
                totals.finesReported += 1
                totals.finesReportedAED += amount
            }
        }
        return totals
    }
}

/// Pure causality rule — kept free of SwiftData so the boundaries are unit-testable.
enum InterventionResolver {
    static func isDecisive(firedAt: Date, deadline: Date, actionAt: Date) -> Bool {
        actionAt >= firedAt && actionAt < deadline
    }
}

/// Store operations. Mirrors NotificationManager's stable-identifier semantics:
/// at most one *unfired* pending event per kind (re-scheduling updates it in
/// place), while fired events stay pending until resolved or past deadline.
enum InterventionLog {
    static func pendingEvents(in context: ModelContext) -> [InterventionEvent] {
        let pending = InterventionOutcome.pending.rawValue
        let descriptor = FetchDescriptor<InterventionEvent>(
            predicate: #Predicate { $0.outcomeRaw == pending })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Log alongside every layer-3/4 schedule call.
    static func upsertScheduled(kind: InterventionKind, zone: String, fireAt: Date,
                                deadline: Date, sessionID: UUID?,
                                in context: ModelContext, now: Date = .now) {
        guard fireAt < deadline else { return }
        if let unfired = pendingEvents(in: context)
            .first(where: { $0.kind == kind && $0.firedAt > now }) {
            unfired.firedAt = fireAt
            unfired.deadline = deadline
            unfired.zoneCode = zone
            unfired.relatedSessionID = sessionID
        } else {
            context.insert(InterventionEvent(kind: kind, firedAt: fireAt, deadline: deadline,
                                             zoneCode: zone, relatedSessionID: sessionID))
        }
    }

    /// Call alongside every cancel: a reminder cancelled before it fired never
    /// reached the user, so it can't have caused anything — drop the record.
    static func discardUnfired(kinds: [InterventionKind],
                               in context: ModelContext, now: Date = .now) {
        for event in pendingEvents(in: context)
        where kinds.contains(event.kind) && event.firedAt > now {
            context.delete(event)
        }
    }

    /// Fired events whose deadline passed without action resolve to `dismissed` —
    /// "expiry warning fired, session lapsed with no extend" is not a save.
    static func closePastDeadline(in context: ModelContext, now: Date = .now) {
        for event in pendingEvents(in: context) where now >= event.deadline {
            event.outcome = .dismissed
            event.resolvedAt = now
        }
    }

    private static func sessionHasDecisiveSave(_ sessionID: UUID, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<InterventionEvent>(
            predicate: #Predicate { $0.decisive && $0.relatedSessionID == sessionID })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// A confirmed payment resolves fired morning/nag interventions for that zone.
    /// At most one becomes decisive per session — the most recently fired wins.
    static func resolvePayment(zone: String, sessionID: UUID, at paidAt: Date,
                               in context: ModelContext) {
        let candidates = pendingEvents(in: context)
            .filter { ($0.kind == .morningFreeToPaid || $0.kind == .unpaidNag)
                      && $0.firedAt <= paidAt
                      && ($0.zoneCode.isEmpty || $0.zoneCode == zone) }
            .sorted { $0.firedAt > $1.firedAt }
        var awarded = sessionHasDecisiveSave(sessionID, in: context)
        for event in candidates {
            event.outcome = .resolvedPaid
            event.resolvedAt = paidAt
            event.relatedSessionID = sessionID
            if !awarded, InterventionResolver.isDecisive(
                firedAt: event.firedAt, deadline: event.deadline, actionAt: paidAt) {
                event.decisive = true
                event.estimatedFineAvoidedAED = ParkinRules.assumedFineAED
                awarded = true
            }
        }
    }

    /// A session voided because its payment actually failed: pending events go,
    /// and any resolved/decisive credit is revoked — the "payment" that earned
    /// it never happened.
    static func voidSession(sessionID: UUID, in context: ModelContext) {
        let events = (try? context.fetch(FetchDescriptor<InterventionEvent>(
            predicate: #Predicate { $0.relatedSessionID == sessionID }))) ?? []
        for event in events {
            if event.outcome == .pending {
                context.delete(event)
            } else {
                event.outcome = .dismissed
                event.decisive = false
                event.estimatedFineAvoidedAED = 0
            }
        }
    }

    /// "I actually got fined" (Task 2): ground truth wins. Every intervention
    /// tied to the session loses its save credit and records the real fine, so
    /// the ledger can never show a fine as avoided that actually happened.
    static func reportFine(sessionID: UUID, amountAED: Decimal,
                           at date: Date = .now, in context: ModelContext) {
        var events = (try? context.fetch(FetchDescriptor<InterventionEvent>(
            predicate: #Predicate { $0.relatedSessionID == sessionID }))) ?? []
        if events.isEmpty {
            // No reminder ever covered this session — still record the fine so
            // the accuracy stats stay honest. Kind approximates the cause.
            let marker = InterventionEvent(kind: .expiryWarning, firedAt: date,
                                           deadline: date, zoneCode: "",
                                           relatedSessionID: sessionID)
            context.insert(marker)
            events = [marker]
        }
        for event in events {
            event.outcome = .gotFined
            event.decisive = false
            event.estimatedFineAvoidedAED = 0
            event.reportedFineAED = amountAED
            event.finedAt = date
            event.resolvedAt = date
        }
    }

    /// An extension resolves fired expiry warnings for that session.
    static func resolveExtend(sessionID: UUID, at extendedAt: Date,
                              in context: ModelContext) {
        let candidates = pendingEvents(in: context)
            .filter { $0.kind == .expiryWarning
                      && $0.relatedSessionID == sessionID
                      && $0.firedAt <= extendedAt }
        var awarded = sessionHasDecisiveSave(sessionID, in: context)
        for event in candidates {
            event.outcome = .resolvedExtended
            event.resolvedAt = extendedAt
            if !awarded, InterventionResolver.isDecisive(
                firedAt: event.firedAt, deadline: event.deadline, actionAt: extendedAt) {
                event.decisive = true
                event.estimatedFineAvoidedAED = ParkinRules.assumedFineAED
                awarded = true
            }
        }
    }
}
