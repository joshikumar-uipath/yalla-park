import AppIntents
import Foundation
import UIKit

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

/// The Bluetooth-disconnect automation's action. Field-proven necessity
/// (tester report 2026-08-09): iOS refuses to LAUNCH an app from an
/// automation while the phone is locked — and it's locked in your pocket at
/// exactly the moment you leave the car. This intent runs in the BACKGROUND
/// (no launch, works locked) and fires the pay-nudge notification instead;
/// tapping that opens the app with Face ID doing the unlock naturally.
struct CarParkedIntent: AppIntent {
    static var title: LocalizedStringResource = "Car parked — remind me"
    static var description = IntentDescription(
        "For the Bluetooth automation: works even while the phone is locked — sends an instant tap-to-pay notification.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        // The automation fired — layer 1 is verified working. Locked state
        // is the exact evidence the Fathima incident lacked.
        Diag.log("intent_fired", ["locked": !UIApplication.shared.isProtectedDataAvailable])
        UserDefaults.standard.set(true, forKey: "automationVerified")
        NotificationManager.shared.fireParkedNudge()
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
