import Foundation

/// ALL Dubai Parkin domain rules live here — never scattered in code.
/// Treat as data that can change; a future milestone may load overrides remotely
/// or from user corrections (per-zone rule overrides on Spot).
///
/// NOTE on paid days: since Dubai's 2022 weekend change, standard zones charge
/// Monday–Saturday and are free on SUNDAYS (not Fridays). Sources still disagree
/// for some premium zones, so kinds are modelled separately and user-correctable.
enum ZoneKind: String, Codable, CaseIterable {
    case standard      // street A/B/C/D zones
    case premium       // charged every day
    case multistorey   // charged 24/7
    /// User-corrected: no Parkin zone at this spot (§10 "their correction
    /// improves their own accuracy"). Field-proven necessary: whole districts
    /// (e.g. Jebel Ali First) have no paid parking, and the app must be able
    /// to remember that instead of demanding payment forever.
    case free
}

struct Verdict: Equatable {
    var paymentRequired: Bool
    var reason: String
    /// When the current state flips (paid→free or free→paid). Nil = never (24/7).
    var nextChange: Date?
}

enum ParkinRules {
    // Payment channels
    // Hand-off to Parkin's own app (their zone DB does the detecting; we do
    // the reminding). Scheme unverified-official; store page is the fallback.
    static let parkinAppScheme = "parkin://"
    static let parkinAppStoreURL = "https://apps.apple.com/ae/app/parkin/id6657993734"
    static let smsNumber = "7275"
    static let whatsappNumber = "971588009090" // Parkin "Mahboub" chatbot, secondary path
    static let smsCarrierFeeAED = 0.30
    static let extendReply = "Y"

    // Enforcement window (standard + premium street zones)
    static let paidStartHour = 8
    static let paidEndHour = 22
    static let freeWeekday = 1 // Calendar weekday: 1 == Sunday

    // Savings model (Task 1) — every tunable lives here, not inline.
    /// Estimated value of one avoided fine, for the ledger. Always shown as "~".
    static let assumedFineAED: Decimal = 150
    /// Layer-4 nag fires this long after a paid-zone screen is left unpaid.
    static let nagDelay: TimeInterval = 5 * 60
    /// A payment within this window of a fired nag counts as caused by it.
    static let nagResolveWindow: TimeInterval = 30 * 60
    /// Expiry warning fires this long before a session lapses.
    static let expiryWarningLead: TimeInterval = 10 * 60

    // Cost estimates ONLY — never present as exact. Zone letter is a hint.
    static func estimatedRateAED(zone: String, kind: ZoneKind) -> Int {
        switch kind {
        case .free: return 0
        case .multistorey: return 5
        case .premium: return 10
        case .standard:
            let letter = zone.uppercased().last
            return (letter == "A" || letter == "C") ? 4 : 2
        }
    }

    /// UAE public holidays; Islamic dates are announced by moon sighting — update
    /// when official. Format yyyy-MM-dd in Asia/Dubai.
    static let publicHolidays: Set<String> = [
        "2026-01-01",
        "2026-03-19", "2026-03-20", "2026-03-21", "2026-03-22",
        "2026-05-26", "2026-05-27", "2026-05-28", "2026-05-29",
        "2026-06-16",
        "2026-08-25",
        "2026-12-02", "2026-12-03",
    ]

    static func smsBody(plate: String, zone: String, hours: Int) -> String {
        // Dubai plates send bare. Other emirates need a prefix — NOT yet verified
        // against the official Parkin page, so v1 supports Dubai plates only.
        let cleanPlate = plate.replacingOccurrences(of: " ", with: "").uppercased()
        return "\(cleanPlate) \(zone.uppercased()) \(hours)"
    }

    // MARK: - Free/paid decision

    private static var dubaiCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dubai") ?? .current
        return cal
    }

    private static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = dubaiCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isPublicHoliday(_ date: Date) -> Bool {
        publicHolidays.contains(dateKey(date))
    }

    private static func isChargedDay(_ kind: ZoneKind, _ date: Date) -> Bool {
        switch kind {
        case .free: return false
        case .multistorey, .premium: return true
        case .standard:
            if dubaiCalendar.component(.weekday, from: date) == freeWeekday { return false }
            if isPublicHoliday(date) { return false }
            return true
        }
    }

    private static func at(hour: Int, of date: Date) -> Date {
        dubaiCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    static func nextPaidStart(kind: ZoneKind, after date: Date) -> Date? {
        guard kind != .multistorey, kind != .free else { return nil }
        for offset in 0..<30 {
            guard let day = dubaiCalendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard isChargedDay(kind, day) else { continue }
            let start = at(hour: paidStartHour, of: day)
            if start > date { return start }
        }
        return nil
    }

    static func verdict(kind: ZoneKind, at date: Date = .now) -> Verdict {
        if kind == .free {
            return Verdict(paymentRequired: false,
                           reason: String(localized: "You marked this spot free"),
                           nextChange: nil)
        }
        if kind == .multistorey {
            return Verdict(paymentRequired: true,
                           reason: String(localized: "Multi-storey car park — paid 24/7"),
                           nextChange: nil)
        }
        let start = at(hour: paidStartHour, of: date)
        let end = at(hour: paidEndHour, of: date)
        let chargedToday = isChargedDay(kind, date)
        let inWindow = date >= start && date < end

        if chargedToday && inWindow {
            return Verdict(paymentRequired: true,
                           reason: String(localized: "Charging until 10:00 PM"),
                           nextChange: end)
        }
        let reason: String
        if !chargedToday {
            reason = dubaiCalendar.component(.weekday, from: date) == freeWeekday
                ? String(localized: "Sundays are free")
                : String(localized: "Public holiday — free")
        } else {
            reason = String(localized: "Free until 8:00 AM")
        }
        return Verdict(paymentRequired: false, reason: reason,
                       nextChange: nextPaidStart(kind: kind, after: date))
    }

    /// Cap durations so a session never silently spills past 22:00 on street zones.
    static func maxPayableHours(kind: ZoneKind, at date: Date = .now) -> Int {
        guard kind != .multistorey else { return 24 }
        let end = at(hour: paidEndHour, of: date)
        let remaining = end.timeIntervalSince(date) / 3600
        return max(1, Int(remaining.rounded(.down)))
    }
}
