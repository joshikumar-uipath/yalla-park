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

    var zoneKind: ZoneKind { ZoneKind(rawValue: zoneKindRaw) ?? .standard }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, zoneCode: String, kind: ZoneKind) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.zoneCode = zoneCode
        self.zoneKindRaw = kind.rawValue
        self.timesParked = 1
        self.lastParkedAt = .now
    }

    /// Spot-match radius per spec §8 (~40 m).
    static let matchRadiusMeters: CLLocationDistance = 40

    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
