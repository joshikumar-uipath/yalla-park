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
    /// Mawaqif (AUH 3009) writes the plate the same way: "DXBA 12345".
    var parkonicPlate: String { "\(emirate.rawValue)\(letters) \(number)" }

    /// Fully spaced style (Ajman 5155, Fujairah 3009): "DXB BB 60925".
    /// Letterless plates collapse cleanly to "DXB 60925".
    var spacedPlate: String {
        letters.isEmpty ? "\(emirate.rawValue) \(number)"
                        : "\(emirate.rawValue) \(letters) \(number)"
    }

    /// Sharjah 5566 style: no plate letters at all — "DXB 60925".
    var sharjahPlate: String { "\(emirate.rawValue) \(number)" }

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

/// What the zone field means for a given operator.
enum ZoneStyle {
    case community   // Parkin: number from GPS + letter off the sign (318C)
    case pZone       // Parkonic: whole code off the pole sign (P105)
    case tier        // Mawaqif: S (standard) or P (premium) kerb — no zones
    case none        // Sharjah / Ajman / Fujairah: one SMS covers the emirate
}

/// How an active session gets longer.
enum ExtendMethod: Equatable {
    case resendPayment        // send the full payment SMS again
    case reply(String)        // prefill a bare "Y" / "E" to the operator
}

enum ParkingOperator: String, Codable, CaseIterable {
    case parkin
    case parkonic
    case mawaqif    // Abu Dhabi
    case sharjah
    case ajman
    case fujairah

    var label: String {
        switch self {
        case .parkin: return "RTA Parkin"
        case .parkonic: return "Parkonic"
        case .mawaqif: return "Mawaqif"
        case .sharjah: return "Sharjah Parking"
        case .ajman: return "Ajman Parking"
        case .fujairah: return "Fujairah Parking"
        }
    }

    var regionLabel: String {
        switch self {
        case .parkin, .parkonic: return "Dubai"
        case .mawaqif: return "Abu Dhabi"
        case .sharjah: return "Sharjah"
        case .ajman: return "Ajman"
        case .fujairah: return "Fujairah"
        }
    }

    var smsNumber: String {
        switch self {
        case .parkin: return ParkinRules.smsNumber
        case .parkonic: return ParkonicRules.smsNumber
        case .mawaqif, .fujairah: return "3009"
        case .sharjah: return "5566"
        case .ajman: return "5155"
        }
    }

    var zoneStyle: ZoneStyle {
        switch self {
        case .parkin: return .community
        case .parkonic: return .pZone
        case .mawaqif: return .tier
        case .sharjah, .ajman, .fujairah: return .none
        }
    }

    var extendMethod: ExtendMethod {
        switch self {
        case .parkin, .sharjah: return .resendPayment
        case .parkonic, .ajman: return .reply("Y")
        case .mawaqif, .fujairah: return .reply("E")
        }
    }

    /// Longest single SMS purchase the operator accepts.
    var maxHoursPerSMS: Int {
        switch self {
        case .ajman: return 1     // one hour at a time; extend by replying Y
        case .sharjah: return 5
        default: return 24
        }
    }

    /// Rough AED/hour for the pay button. Nil = unpublished (Parkonic) — the
    /// UI shows no price and lets the operator's reply SMS state the fee.
    func estimatedRateAED(zone: String) -> Int? {
        switch self {
        case .parkin: return nil  // callers use ParkinRules.estimatedRateAED (kind-aware)
        case .parkonic: return nil
        case .mawaqif: return zone.uppercased() == "P" ? 3 : 2
        case .sharjah, .ajman, .fujairah: return 2
        }
    }

    /// Estimated value of one avoided fine for the savings ledger — always
    /// presented with "~". Regional fine scales differ.
    var assumedFineAED: Decimal {
        switch self {
        case .parkin, .parkonic: return ParkinRules.assumedFineAED  // 150
        case .mawaqif: return 200
        case .sharjah, .ajman, .fujairah: return 100
        }
    }

    func smsBody(plate: PlateProfile, zone: String, hours: Int) -> String {
        switch self {
        case .parkin:
            return ParkinRules.smsBody(plate: plate.parkinPlate, zone: zone, hours: hours)
        case .parkonic:
            return ParkonicRules.smsBody(plate: plate, zone: zone, hours: hours)
        case .mawaqif:
            // "DXBA 12345 S 1" — plate fused like Parkonic, then S/P tier.
            let tier = zone.uppercased() == "P" ? "P" : "S"
            return "\(plate.parkonicPlate) \(tier) \(hours)"
        case .sharjah:
            // "DXB 41190 3" — no letters, no zones. FIELD-VERIFIED 2026-08-28
            // at Khor Fakkan: 5566 confirmed ticket 250763373, AED 8.38, 3 h.
            return "\(plate.sharjahPlate) \(hours)"
        case .ajman, .fujairah:
            // "DXB BB 60925 1" — fully spaced.
            return "\(plate.spacedPlate) \(hours)"
        }
    }
}

/// Operator-aware zone label (app target only — widgets use the 1-arg form
/// in Theme.swift). Zone-less operators show their name instead of a code.
func zoneLabel(_ code: String, operator parkingOperator: ParkingOperator) -> String {
    if code.isEmpty {
        return parkingOperator == .parkin
            ? String(localized: "via Parkin app")
            : parkingOperator.label
    }
    if parkingOperator == .mawaqif {
        return code.uppercased() == "P" ? "Mawaqif · Premium" : "Mawaqif · Standard"
    }
    return "Zone \(code)"
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
