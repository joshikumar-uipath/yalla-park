import Foundation
import WidgetKit

/// Snapshot of the active paid session, shared with the widget extension
/// through the app group so the home-screen widget can count down.
struct WidgetSession: Codable, Equatable {
    var zoneCode: String
    var plate: String
    var startedAt: Date
    var expiresAt: Date
}

enum WidgetSessionStore {
    static let appGroupID = "group.com.avjoshi.dxbpark"
    static let widgetKind = "ParkNowWidget"
    private static let key = "widgetSession"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func save(zoneCode: String, plate: String, startedAt: Date, expiresAt: Date) {
        let session = WidgetSession(zoneCode: zoneCode, plate: plate,
                                    startedAt: startedAt, expiresAt: expiresAt)
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults?.set(data, forKey: key)
        reloadWidget()
    }

    /// Extend keeps zone/plate — only the dates move.
    static func update(startedAt: Date, expiresAt: Date) {
        guard var session = stored() else { return }
        session.startedAt = startedAt
        session.expiresAt = expiresAt
        save(zoneCode: session.zoneCode, plate: session.plate,
             startedAt: session.startedAt, expiresAt: session.expiresAt)
    }

    static func clear() {
        guard defaults?.data(forKey: key) != nil else { return }
        defaults?.removeObject(forKey: key)
        reloadWidget()
    }

    /// The active session, or nil if none/expired.
    static func load(at date: Date = .now) -> WidgetSession? {
        guard let session = stored(), session.expiresAt > date else { return nil }
        return session
    }

    private static func stored() -> WidgetSession? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSession.self, from: data)
    }

    private static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
