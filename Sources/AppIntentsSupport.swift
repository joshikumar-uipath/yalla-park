import AppIntents
import Foundation

/// "Hey Siri, I just parked" — opens the app straight into the parked flow (§12).
struct ParkNowIntent: AppIntent {
    static var title: LocalizedStringResource = "I just parked"
    static var description = IntentDescription("Check the zone and pay for parking in two taps.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .parkNowIntent, object: nil)
        return .result()
    }
}

/// "Hey Siri, extend my parking" — jumps into the +1 hour flow.
struct ExtendParkingIntent: AppIntent {
    static var title: LocalizedStringResource = "Extend my parking"
    static var description = IntentDescription("Extend the active parking session by one hour.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .extendParkingIntent, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let parkNowIntent = Notification.Name("parkNowIntent")
    static let extendParkingIntent = Notification.Name("extendParkingIntent")
}

struct YallaParkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParkNowIntent(),
            phrases: [
                "I just parked with \(.applicationName)",
                "\(.applicationName), I just parked",
            ],
            shortTitle: "I just parked",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: ExtendParkingIntent(),
            phrases: [
                "Extend my parking with \(.applicationName)",
                "\(.applicationName), extend my parking",
            ],
            shortTitle: "Extend parking",
            systemImageName: "plus.circle.fill"
        )
    }
}
