import Foundation
import UserNotifications

/// The four defense layers (§9). Layer 1 is the Shortcuts trigger and layer 2 is the
/// two-tap pay flow; this manager owns layers 3 and 4 — every scheduled local
/// notification in the app, with stable identifiers so re-scheduling replaces cleanly.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set by the App at launch — deep-link handlers.
    var onOpenParked: (() -> Void)?
    var onExtendRequested: (() -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var defaults: UserDefaults { .standard }

    enum ID {
        static let morning = "layer3-morning-before-paid"
        static let nag = "layer4-unpaid-nag"
        static let expirySoon = "layer4-expiry-soon"
        static let expired = "layer4-expired"
    }
    enum CategoryID { static let expiry = "SESSION_EXPIRY" }
    enum ActionID { static let extend1h = "EXTEND_1H" }

    // User preferences (Settings), all default-on.
    private var remindMorning: Bool { defaults.object(forKey: "remindMorning") as? Bool ?? true }
    private var remindNag: Bool { defaults.object(forKey: "remindNag") as? Bool ?? true }
    private var remindExpiry: Bool { defaults.object(forKey: "remindExpiry") as? Bool ?? true }
    private var morningLeadMinutes: Int { defaults.object(forKey: "morningLeadMinutes") as? Int ?? 15 }

    func configure() {
        center.delegate = self
        let extend = UNNotificationAction(identifier: ActionID.extend1h,
                                          title: "+1 hour",
                                          options: [.foreground])
        let expiry = UNNotificationCategory(identifier: CategoryID.expiry,
                                            actions: [extend],
                                            intentIdentifiers: [],
                                            options: [])
        center.setNotificationCategories([expiry])
    }

    func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    // MARK: - Layer 3: free now, paid later

    func scheduleMorningReminder(zone: String, paidStart: Date) {
        guard remindMorning else { return }
        let fire = paidStart.addingTimeInterval(-Double(morningLeadMinutes) * 60)
        let startText = paidStart.formatted(date: .omitted, time: .shortened)
        schedule(id: ID.morning,
                 title: "🅿️ Paid parking starts soon",
                 body: "\(zone) starts charging at \(startText). Pay in two taps or move the car.",
                 at: fire)
    }

    func cancelMorningReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.morning])
    }

    // MARK: - Layer 4a: swipe-away nag

    func scheduleUnpaidNag(zone: String) {
        guard remindNag else { return }
        schedule(id: ID.nag,
                 title: "Parking not registered!",
                 body: "You parked\(zone.isEmpty ? "" : " in zone \(zone)") 5 minutes ago and haven't paid — fines start at AED 150. Tap to pay in two taps.",
                 at: Date.now.addingTimeInterval(5 * 60))
    }

    func cancelUnpaidNag() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.nag])
    }

    // MARK: - Layer 4b: expiry reminders (with lock-screen +1 hr action)

    func scheduleExpiryReminders(zone: String, expiresAt: Date) {
        cancelSessionReminders()
        guard remindExpiry else { return }
        schedule(id: ID.expirySoon,
                 title: "Parking expires in 10 minutes",
                 body: "Zone \(zone) — extend from here if you're staying.",
                 at: expiresAt.addingTimeInterval(-10 * 60),
                 category: CategoryID.expiry)
        schedule(id: ID.expired,
                 title: "Parking expired!",
                 body: "Zone \(zone) — your session has ended. Extend now to avoid a fine.",
                 at: expiresAt,
                 category: CategoryID.expiry)
    }

    func cancelSessionReminders() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.expirySoon, ID.expired])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Testing helper (TestFlight/debug only via Settings): fires one of each layer within seconds.
    func fireTestNotifications() {
        schedule(id: "debug-morning", title: "🅿️ Paid parking starts soon",
                 body: "Zone 444A starts charging at 8:00 AM. Pay in two taps or move the car.",
                 at: .now.addingTimeInterval(4))
        schedule(id: "debug-expiry", title: "Parking expires in 10 minutes",
                 body: "Zone 444A — extend from here if you're staying.",
                 at: .now.addingTimeInterval(8), category: CategoryID.expiry)
    }

    // MARK: - Plumbing

    private func schedule(id: String, title: String, body: String, at date: Date, category: String? = nil) {
        guard date > .now else { return }
        Task {
            guard await ensureAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let category { content.categoryIdentifier = category }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // Same identifier replaces any pending request — no duplicate stacking (§15).
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // Show banners even while the app is foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if response.actionIdentifier == ActionID.extend1h {
                onExtendRequested?()
            } else {
                // Default tap on any of our notifications → straight to the parked flow.
                onOpenParked?()
            }
        }
    }
}
