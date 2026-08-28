import Foundation

/// The tier gates, centralized. Rule zero (never violated): active-session
/// safety — expiry alerts, nags, the ability to pay — is free forever.
/// Signing in buys MEMORY (spots with zone auto-fill, longer history, the
/// parked-nudge automation). Pro conveniences stay ungated until StoreKit
/// lands, so testers lose nothing before the paywall is real.
enum Tier {
    /// The owner's demo profile counts as fully entitled — his device must
    /// look complete in a presentation without a sign-in dance.
    static var isEntitled: Bool {
        !Account.signInRequired
            || Account.isSignedIn
            || UserDefaults.standard.bool(forKey: "presenterMode")
    }

    // History windows: free keeps a week, signed-in keeps 90 days.
    static let freeHistoryDays = 7
    static let signedInHistoryDays = 90

    /// Sessions older than this stay in the store but leave the feed.
    static func historyCutoff(now: Date = .now, calendar: Calendar = .current) -> Date {
        let days = isEntitled ? signedInHistoryDays : freeHistoryDays
        return calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// Free remembers only your designated places (Home/Office) and free-spot
    /// corrections — zone auto-fill memory for paid spots is the signed-in
    /// everyday magic.
    static var remembersZoneSpots: Bool { isEntitled }

    /// The car-Bluetooth parked nudge is the signed-in automation.
    static var autoNudgeEnabled: Bool { isEntitled }
}
