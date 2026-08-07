import SwiftUI

/// Design tokens extracted from dxb-park-map-pass.html — the visual source of truth.
enum Theme {
    // Colour
    static let coral = Color(hex: 0xFB4E2A)
    static let labelPrimary = Color(hex: 0x1C1C1E)
    static let labelSecondary = Color(hex: 0x8A8A8E)
    static let labelTertiary = Color(hex: 0xBEBEC2)
    static let canvasWarm = Color(hex: 0xE7E4DC)
    static let passCanvasTop = Color(hex: 0xF4F3EF)
    static let passCanvasBottom = Color(hex: 0xEDEBE6)
    static let success = Color(hex: 0x12A150)
    static let paidTagBackground = Color(hex: 0xFFE6DD)
    static let paidTagText = Color(hex: 0xB23A12)
    static let freeTagBackground = Color(hex: 0xDFF4E6)
    static let lowTimeWarning = Color(hex: 0xFFD36B)
    static let segmentedTrack = Color(hex: 0xEFEDE7)
    static let smsPreviewBackground = Color(hex: 0xF1EFE9)

    // Shape
    static let sheetRadius: CGFloat = 28
    static let cardRadius: CGFloat = 26
    static let buttonRadius: CGFloat = 17
    static let segmentedTrackRadius: CGFloat = 15
    static let segmentedThumbRadius: CGFloat = 11

    // Motion
    static let sheetSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let crossFade = Animation.easeInOut(duration: 0.35)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Zone display label shared across app + widgets: Parkin-app payments may not
/// carry a zone code — never render a dangling "Zone ". (The app proper uses
/// the operator-aware overload in Operators.swift; widgets have no operator in
/// their shared store yet, so they call this form.)
func zoneLabel(_ code: String) -> String {
    code.isEmpty ? String(localized: "via Parkin app") : "Zone \(code)"
}
