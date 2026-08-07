import Foundation
import CoreLocation

/// Per-region enforcement calendars + a generic verdict engine (Phase 2), and
/// coarse emirate geofences for operator auto-detection (Phase 3).
///
/// Dubai (Parkin/Parkonic) keeps using ParkinRules.verdict unchanged — the
/// engine here serves the other emirates, whose calendars differ in shape:
/// Ajman charges in TWO windows a day, Sharjah unified to 8:00–midnight
/// DAILY (no free Friday, holidays paid) on 1 Jul 2026.

struct PaidWindow: Equatable {
    let startHour: Int
    let endHour: Int    // 24 == midnight
}

struct RegionCalendar {
    let windows: [PaidWindow]
    /// Calendar weekday numbers that are free all day (1 = Sunday, 6 = Friday).
    let freeWeekdays: Set<Int>
    let freeOnPublicHolidays: Bool
}

enum RegionRules {
    static func calendar(for parkingOperator: ParkingOperator) -> RegionCalendar {
        switch parkingOperator {
        case .parkin, .parkonic:
            // Dubai: Mon–Sat 08–22, Sundays + holidays free (ParkinRules).
            return RegionCalendar(windows: [PaidWindow(startHour: 8, endHour: 22)],
                                  freeWeekdays: [1], freeOnPublicHolidays: true)
        case .mawaqif:
            // Abu Dhabi: Mon–Sat 08:00–24:00, Sundays free.
            return RegionCalendar(windows: [PaidWindow(startHour: 8, endHour: 24)],
                                  freeWeekdays: [1], freeOnPublicHolidays: true)
        case .sharjah:
            // Unified 1 Jul 2026: 08:00–midnight EVERY day, holidays included.
            return RegionCalendar(windows: [PaidWindow(startHour: 8, endHour: 24)],
                                  freeWeekdays: [], freeOnPublicHolidays: false)
        case .ajman:
            // Sat–Thu, split windows 08–13 and 17–22; Fridays free.
            return RegionCalendar(windows: [PaidWindow(startHour: 8, endHour: 13),
                                            PaidWindow(startHour: 17, endHour: 22)],
                                  freeWeekdays: [6], freeOnPublicHolidays: true)
        case .fujairah:
            // Best public info (unverified in the field): Sat–Thu 08–22.
            return RegionCalendar(windows: [PaidWindow(startHour: 8, endHour: 22)],
                                  freeWeekdays: [6], freeOnPublicHolidays: true)
        }
    }

    // MARK: - Generic verdict

    private static var localCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dubai") ?? .current
        return cal
    }

    private static func at(hour: Int, of date: Date) -> Date {
        let start = localCalendar.startOfDay(for: date)
        return localCalendar.date(byAdding: .hour, value: hour, to: start) ?? date
    }

    private static func isChargedDay(_ regionCalendar: RegionCalendar, _ date: Date) -> Bool {
        if regionCalendar.freeWeekdays.contains(localCalendar.component(.weekday, from: date)) {
            return false
        }
        if regionCalendar.freeOnPublicHolidays && ParkinRules.isPublicHoliday(date) {
            return false
        }
        return true
    }

    private static func hourText(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return String(localized: "midnight")
        case 12: return String(localized: "noon")
        case let h where h < 12: return "\(h):00 AM"
        default: return "\(hour - 12):00 PM"
        }
    }

    /// Next moment charging begins, scanning up to 30 days ahead.
    static func nextPaidStart(for parkingOperator: ParkingOperator, after date: Date) -> Date? {
        let regionCalendar = calendar(for: parkingOperator)
        for offset in 0..<30 {
            guard let day = localCalendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard isChargedDay(regionCalendar, day) else { continue }
            for window in regionCalendar.windows {
                let start = at(hour: window.startHour, of: day)
                if start > date { return start }
            }
        }
        return nil
    }

    /// Verdict for any operator. Dubai delegates to ParkinRules so the
    /// long-standing boundary-tested behavior stays byte-identical.
    static func verdict(for parkingOperator: ParkingOperator, kind: ZoneKind,
                        at date: Date = .now) -> Verdict {
        switch parkingOperator {
        case .parkin, .parkonic:
            return ParkinRules.verdict(kind: kind, at: date)
        default:
            break
        }
        if kind == .free {
            return Verdict(paymentRequired: false,
                           reason: String(localized: "You marked this spot free"),
                           nextChange: nil)
        }
        let regionCalendar = calendar(for: parkingOperator)
        if isChargedDay(regionCalendar, date) {
            for window in regionCalendar.windows {
                let start = at(hour: window.startHour, of: date)
                let end = at(hour: window.endHour, of: date)
                if date >= start && date < end {
                    return Verdict(
                        paymentRequired: true,
                        reason: String(localized: "Charging until \(hourText(window.endHour))"),
                        nextChange: end)
                }
            }
        }
        // Free right now — name why, and when that changes.
        let next = nextPaidStart(for: parkingOperator, after: date)
        let reason: String
        if !isChargedDay(regionCalendar, date) {
            reason = ParkinRules.isPublicHoliday(date) && regionCalendar.freeOnPublicHolidays
                ? String(localized: "Public holiday — free")
                : String(localized: "Free today in \(parkingOperator.regionLabel)")
        } else if let next {
            reason = String(localized: "Free until \(next.formatted(date: .omitted, time: .shortened))")
        } else {
            reason = String(localized: "Free right now")
        }
        return Verdict(paymentRequired: false, reason: reason, nextChange: next)
    }

    /// Hours until the current paid window ends — a session should never
    /// silently spill past it. Dubai delegates to ParkinRules.
    static func maxPayableHours(for parkingOperator: ParkingOperator, kind: ZoneKind,
                                at date: Date = .now) -> Int {
        switch parkingOperator {
        case .parkin, .parkonic:
            return ParkinRules.maxPayableHours(kind: kind, at: date)
        default:
            break
        }
        let regionCalendar = calendar(for: parkingOperator)
        for window in regionCalendar.windows {
            let start = at(hour: window.startHour, of: date)
            let end = at(hour: window.endHour, of: date)
            if date >= start && date < end {
                return max(1, Int((end.timeIntervalSince(date) / 3600).rounded(.down)))
            }
        }
        return 1
    }
}

// MARK: - Emirate geofences (Phase 3)

/// Coarse bounding boxes for non-Dubai parking regions. Deliberately checked
/// ONLY when the Dubai community polygons return nothing — precise Dubai
/// polygons always win, so box overlap near the Dubai border is harmless.
/// Order matters: Ajman sits against Sharjah, and Sharjah's east-coast towns
/// (Khor Fakkan, Kalba) sit inside the Fujairah strip — first hit wins.
enum EmirateLocator {
    private struct Box {
        let minLat, maxLat, minLon, maxLon: Double
        let parkingOperator: ParkingOperator
    }

    private static let boxes: [Box] = [
        // Ajman city (checked before Sharjah — they share a border street).
        Box(minLat: 25.375, maxLat: 25.47, minLon: 55.40, maxLon: 55.57, parkingOperator: .ajman),
        // Sharjah city.
        Box(minLat: 25.26, maxLat: 25.375, minLon: 55.35, maxLon: 55.65, parkingOperator: .sharjah),
        // Sharjah east-coast exclaves — Khor Fakkan, then Kalba.
        Box(minLat: 25.30, maxLat: 25.40, minLon: 56.28, maxLon: 56.40, parkingOperator: .sharjah),
        Box(minLat: 24.96, maxLat: 25.10, minLon: 56.30, maxLon: 56.40, parkingOperator: .sharjah),
        // Fujairah city strip.
        Box(minLat: 25.05, maxLat: 25.30, minLon: 56.25, maxLon: 56.42, parkingOperator: .fujairah),
        // Abu Dhabi city + suburbs.
        Box(minLat: 24.25, maxLat: 24.62, minLon: 54.27, maxLon: 54.80, parkingOperator: .mawaqif),
        // Al Ain (Mawaqif too).
        Box(minLat: 24.05, maxLat: 24.35, minLon: 55.55, maxLon: 55.90, parkingOperator: .mawaqif),
    ]

    /// The non-Dubai operator at this coordinate, or nil (Dubai or unknown).
    static func parkingOperator(at coordinate: CLLocationCoordinate2D) -> ParkingOperator? {
        boxes.first {
            coordinate.latitude >= $0.minLat && coordinate.latitude <= $0.maxLat
                && coordinate.longitude >= $0.minLon && coordinate.longitude <= $0.maxLon
        }?.parkingOperator
    }
}
