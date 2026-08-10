import Foundation
import UserNotifications

/// The four defense layers (§9). Layer 1 is the Shortcuts trigger and layer 2 is the
/// two-tap pay flow; this manager owns layers 3 and 4 — every scheduled local
/// notification in the app, with stable identifiers so re-scheduling replaces cleanly.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set by the App at launch — deep-link handlers. A notification tap can
    /// cold-launch the app before the UI wires these up, so an unhandled tap is
    /// parked in `pendingAction` and replayed the moment its handler arrives.
    var onOpenParked: (() -> Void)? { didSet { replayPendingAction() } }
    var onExtendRequested: (() -> Void)? { didSet { replayPendingAction() } }

    private enum PendingAction { case openParked, extend }
    private var pendingAction: PendingAction?

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

    // User preferences (Settings), all default-on. Internal so the intervention
    // log can gate on them — an off layer must never produce a "save".
    var remindMorning: Bool { defaults.object(forKey: "remindMorning") as? Bool ?? true }
    var remindNag: Bool { defaults.object(forKey: "remindNag") as? Bool ?? true }
    var remindExpiry: Bool { defaults.object(forKey: "remindExpiry") as? Bool ?? true }
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
                 at: Date.now.addingTimeInterval(ParkinRules.nagDelay))
    }

    func cancelUnpaidNag() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.nag])
    }

    // MARK: - Layer 1: the parked nudge (Bluetooth automation, locked phone)

    /// Fired by CarParkedIntent the moment the car's Bluetooth drops. The
    /// automation can't LAUNCH the app while the phone is locked (iOS rule,
    /// tester-reported), so this notification is the bridge: tap → unlock →
    /// straight into the parked flow (default tap = openParked).
    func fireParkedNudge() {
        schedule(id: "layer1-parked-nudge",
                 title: "Just parked?",
                 body: "Tap to check the zone and pay before you walk away.",
                 at: .now.addingTimeInterval(1.5))
    }

    // MARK: - Layer 4b: expiry reminders (with lock-screen +1 hr action)

    /// `zoneText` is the READY display label ("Zone 318C", "Sharjah Parking")
    /// — callers format it with zoneLabel(_:operator:) so zone-less regions
    /// never read "via Parkin app" here. Identifiers are PER SESSION so two
    /// parallel tickets (multi-zone parking) each keep their own pair;
    /// re-scheduling the same session replaces cleanly via identical IDs.
    func scheduleExpiryReminders(sessionID: UUID, zoneText: String, expiresAt: Date) {
        guard remindExpiry else { return }
        let userInfo: [AnyHashable: Any] = ["sessionID": sessionID.uuidString]
        schedule(id: "\(ID.expirySoon)-\(sessionID.uuidString)",
                 title: "Parking expires in 10 minutes",
                 body: "\(zoneText) — extend from here if you're staying.",
                 at: expiresAt.addingTimeInterval(-ParkinRules.expiryWarningLead),
                 category: CategoryID.expiry, userInfo: userInfo)
        schedule(id: "\(ID.expired)-\(sessionID.uuidString)",
                 title: "Parking expired!",
                 body: "\(zoneText) — your session has ended. Extend now to avoid a fine.",
                 at: expiresAt,
                 category: CategoryID.expiry, userInfo: userInfo)
    }

    func cancelSessionReminders(sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(ID.expirySoon)-\(sessionID.uuidString)",
            "\(ID.expired)-\(sessionID.uuidString)",
            // Legacy fixed IDs from pre-multi-ticket builds.
            ID.expirySoon, ID.expired,
        ])
    }

    /// Which session an "+1 hour" notification action was about — read by the
    /// extend flow so the RIGHT ticket gets extended when two are running.
    var extendTargetSessionID: UUID?

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

    private func schedule(id: String, title: String, body: String, at date: Date,
                          category: String? = nil, userInfo: [AnyHashable: Any]? = nil) {
        guard date > .now else { return }
        Task {
            guard await ensureAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // Fine-avoidance is exactly what Time Sensitive exists for: these
            // must break through Focus (on a call, Work, Driving) or they're
            // worthless — field report: nag silenced by an on-call Focus.
            content.interruptionLevel = .timeSensitive
            if let category { content.categoryIdentifier = category }
            if let userInfo { content.userInfo = userInfo }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // Same identifier replaces any pending request — no duplicate stacking (§15).
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            Diag.log("notif_scheduled", ["id": id, "at": ISO8601DateFormatter().string(from: date)])
        }
    }

    // NOTE: these MUST be the completionHandler variants, not the async ones.
    // The async forms resume UIKit's post-response state-restoration work on a
    // Swift-concurrency thread → NSInternalInconsistency assertion → SIGABRT
    // (TestFlight crash 328B0D53, iOS 26.5.2, "closed when I opened the
    // notification"). Handling on main and completing there fixes it.

    // Show banners even while the app is foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            Diag.log("notif_tapped", ["id": response.notification.request.identifier,
                                      "action": response.actionIdentifier])
            // Remember which session the notification was about, so a
            // multi-ticket extend targets the right one.
            if let idString = response.notification.request.content.userInfo["sessionID"] as? String {
                self.extendTargetSessionID = UUID(uuidString: idString)
            }
            if response.actionIdentifier == ActionID.extend1h {
                if let handler = self.onExtendRequested { handler() } else { self.pendingAction = .extend }
            } else {
                // Default tap on any of our notifications → straight to the parked flow.
                if let handler = self.onOpenParked { handler() } else { self.pendingAction = .openParked }
            }
            completionHandler()
        }
    }

    private func replayPendingAction() {
        guard let action = pendingAction else { return }
        switch action {
        case .openParked:
            guard let onOpenParked else { return }
            pendingAction = nil
            onOpenParked()
        case .extend:
            guard let onExtendRequested else { return }
            pendingAction = nil
            onExtendRequested()
        }
    }
}
