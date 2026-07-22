import Foundation
import SwiftData
import CoreLocation

@Model
final class Session {
    var id: UUID
    var plate: String
    var zoneCode: String
    var zoneKindRaw: String
    var startedAt: Date
    var durationHours: Int
    var paymentAttempted: Bool
    var userConfirmedPaid: Bool
    var expiresAt: Date
    var extendedCount: Int
    /// Paid through the Parkin app (not SMS) — extends go back there too.
    var paidViaParkinApp: Bool = false

    var zoneKind: ZoneKind { ZoneKind(rawValue: zoneKindRaw) ?? .standard }

    init(plate: String, zoneCode: String, kind: ZoneKind, durationHours: Int, startedAt: Date = .now) {
        self.id = UUID()
        self.plate = plate
        self.zoneCode = zoneCode
        self.zoneKindRaw = kind.rawValue
        self.startedAt = startedAt
        self.durationHours = durationHours
        self.paymentAttempted = false
        self.userConfirmedPaid = false
        self.expiresAt = startedAt.addingTimeInterval(TimeInterval(durationHours) * 3600)
        self.extendedCount = 0
    }

    var isActive: Bool { userConfirmedPaid && expiresAt > .now }

    func extend(byHours hours: Int = 1) {
        expiresAt = expiresAt.addingTimeInterval(TimeInterval(hours) * 3600)
        durationHours += hours
        extendedCount += 1
    }
}

/// A user-designated place where the app stays silent: the zone may well be
/// paid (for visitors), but the user has their own arrangement there —
/// residence permit, office parking. Distinct from ZoneKind.free, which claims
/// the *place* has no Parkin zone at all.
enum SpotDesignation: String, Codable, CaseIterable {
    case home, office

    var label: String {
        switch self {
        case .home: return String(localized: "Home")
        case .office: return String(localized: "Office")
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .office: return "building.2.fill"
        }
    }
}

@Model
final class Spot {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var zoneCode: String
    var zoneKindRaw: String
    var timesParked: Int
    var lastParkedAt: Date
    var designationRaw: String?

    var zoneKind: ZoneKind { ZoneKind(rawValue: zoneKindRaw) ?? .standard }
    var designation: SpotDesignation? {
        get { designationRaw.flatMap(SpotDesignation.init(rawValue:)) }
        set { designationRaw = newValue?.rawValue }
    }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, zoneCode: String,
         kind: ZoneKind, designation: SpotDesignation? = nil) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.zoneCode = zoneCode
        self.zoneKindRaw = kind.rawValue
        self.timesParked = 1
        self.lastParkedAt = .now
        self.designationRaw = designation?.rawValue
    }

    /// Spot-match radius per spec §8 (~40 m).
    static let matchRadiusMeters: CLLocationDistance = 40
    /// Free spots (home, unzoned districts) match wider — home parking rarely
    /// lands on the exact same 40 m twice, and a false "free" match near a
    /// genuinely free spot is low-risk compared to a missed one that nags.
    static let freeMatchRadiusMeters: CLLocationDistance = 150

    var matchRadius: CLLocationDistance {
        zoneKind == .free || designationRaw != nil
            ? Spot.freeMatchRadiusMeters : Spot.matchRadiusMeters
    }

    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
