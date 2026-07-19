import Foundation
import ActivityKit

/// Starts/updates/ends the lock-screen + Dynamic Island parking meter (§12).
/// One activity at a time — a new session replaces any stale one.
enum LiveActivityManager {
    static func start(zoneCode: String, plate: String, startedAt: Date, expiresAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attributes = ParkingActivityAttributes(zoneCode: zoneCode, plate: plate)
        let state = ParkingActivityAttributes.ContentState(startedAt: startedAt, expiresAt: expiresAt)
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: expiresAt)
        )
    }

    static func update(startedAt: Date, expiresAt: Date) {
        Task {
            let state = ParkingActivityAttributes.ContentState(startedAt: startedAt, expiresAt: expiresAt)
            for activity in Activity<ParkingActivityAttributes>.activities {
                await activity.update(.init(state: state, staleDate: expiresAt))
            }
        }
    }

    static func end() {
        Task {
            for activity in Activity<ParkingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
