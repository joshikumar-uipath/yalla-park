import Foundation
import ActivityKit

/// Shared between the app and the widget extension — the Live Activity contract.
struct ParkingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var expiresAt: Date
    }

    var zoneCode: String
    var plate: String
}
