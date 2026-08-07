import Foundation

/// Multi-operator support, Phase 1 (user brief 2026-08-07): Dubai has TWO
/// on-street parking operators. RTA Parkin (SMS 7275, community zones like
/// 318C) covers most of the city; Parkonic (SMS 6670, P-zones like P105 read
/// off pole signage) runs private-developer communities — JVC, Dubai Silicon
/// Oasis, The Gardens. Each operator writes the same plate differently, so
/// the plate is stored structured, not as one string.

enum Emirate: String, CaseIterable, Identifiable {
    case dubai = "DXB"
    case abuDhabi = "AUH"
    case sharjah = "SHJ"
    case ajman = "AJM"
    case rasAlKhaimah = "RAK"
    case fujairah = "FUJ"
    case ummAlQuwain = "UAQ"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dubai: return "Dubai"
        case .abuDhabi: return "Abu Dhabi"
        case .sharjah: return "Sharjah"
        case .ajman: return "Ajman"
        case .rasAlKhaimah: return "Ras Al Khaimah"
        case .fujairah: return "Fujairah"
        case .ummAlQuwain: return "Umm Al Quwain"
        }
    }
}

/// The plate as three parts. Operators join them differently:
/// Parkin wants "BB60925", Parkonic wants "DXBBB 60925".
struct PlateProfile: Equatable {
    var emirate: Emirate
    var letters: String   // category code, e.g. "BB" — uppercase, no spaces
    var number: String    // digits, e.g. "60925"

    var isComplete: Bool { !number.isEmpty }

    /// Parkin 7275 style: letters+number joined ("BB60925", "A44821").
    var parkinPlate: String { letters + number }

    /// Parkonic 6670 style: emirate code fused to the letters, number spaced
    /// ("DXBBB 60925") — field-verified against a real Parkonic ticket.
    var parkonicPlate: String { "\(emirate.rawValue)\(letters) \(number)" }

    /// Parse a legacy single-string plate ("A44821", "BB 60925") into parts.
    static func parseLegacy(_ raw: String) -> (letters: String, number: String) {
        let cleaned = raw.replacingOccurrences(of: " ", with: "").uppercased()
        let letters = String(cleaned.prefix(while: \.isLetter))
        let number = cleaned.drop(while: \.isLetter).filter(\.isNumber)
        return (letters, String(number))
    }
}

/// One-time migration of the old single-string "plate" key into the
/// structured keys. Idempotent; safe to call every launch.
enum PlateStore {
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        let existing = defaults.string(forKey: "plateNumber") ?? ""
        guard existing.isEmpty,
              let legacy = defaults.string(forKey: "plate"), !legacy.isEmpty
        else { return }
        let parsed = PlateProfile.parseLegacy(legacy)
        guard !parsed.number.isEmpty else { return }
        defaults.set(parsed.letters, forKey: "plateLetters")
        defaults.set(parsed.number, forKey: "plateNumber")
        if defaults.string(forKey: "plateEmirate") == nil {
            defaults.set(Emirate.dubai.rawValue, forKey: "plateEmirate")
        }
    }
}

enum ParkingOperator: String, Codable, CaseIterable {
    case parkin
    case parkonic

    var label: String {
        switch self {
        case .parkin: return "RTA Parkin"
        case .parkonic: return "Parkonic"
        }
    }

    var smsNumber: String {
        switch self {
        case .parkin: return ParkinRules.smsNumber
        case .parkonic: return ParkonicRules.smsNumber
        }
    }

    func smsBody(plate: PlateProfile, zone: String, hours: Int) -> String {
        switch self {
        case .parkin:
            return ParkinRules.smsBody(plate: plate.parkinPlate, zone: zone, hours: hours)
        case .parkonic:
            return ParkonicRules.smsBody(plate: plate, zone: zone, hours: hours)
        }
    }
}

/// Parkonic domain rules. Like ParkinRules: data, not code — treat every
/// constant as revisable when the operator changes something.
enum ParkonicRules {
    static let smsNumber = "6670"
    /// Their ticket SMS says "Reply with Y to extend" — we prefill exactly Y.
    static let extendReply = "Y"
    /// Parkonic SMS payments only work from DU/Etisalat lines (their rule).
    static let simNote = String(localized: "Parkonic SMS works from DU or Etisalat lines only.")

    /// Dubai communities where Parkonic runs on-street parking, keyed by the
    /// same community numbers as the bundled polygons. Field-confirmed by the
    /// user: JVC + The Gardens; DSO from Parkonic's own announcements.
    /// 681 = Al Barsha South Fourth (JVC) · 626 = Nadd Hessa (DSO) ·
    /// 591 = Jabal Ali First (The Gardens / Discovery Gardens — this is why
    /// Parkin rejected "591B": the area was never Parkin's).
    static let communities: Set<Int> = [681, 626, 591]

    static func isParkonicCommunity(_ number: Int) -> Bool {
        communities.contains(number)
    }

    /// "DXBBB 60925 P105 1" — matches the user's field-tested 6670 payment.
    static func smsBody(plate: PlateProfile, zone: String, hours: Int) -> String {
        "\(plate.parkonicPlate) \(normalizeZone(zone)) \(hours)"
    }

    /// P-zones come off the pole sign; digits-only entry gets its P back.
    static func normalizeZone(_ zone: String) -> String {
        let cleaned = zone.replacingOccurrences(of: " ", with: "").uppercased()
        guard !cleaned.isEmpty else { return cleaned }
        return cleaned.hasPrefix("P") ? cleaned : "P\(cleaned)"
    }

    static func isValidZone(_ zone: String) -> Bool {
        let normalized = normalizeZone(zone)
        return normalized.count >= 2
            && normalized.hasPrefix("P")
            && normalized.dropFirst().allSatisfy(\.isNumber)
    }
}
