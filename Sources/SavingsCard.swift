import SwiftUI
import SwiftData
import Charts

/// The savings surface. Money figures come exclusively from decisive
/// InterventionEvents (the honest ledger); activity is counted, never priced.
/// Copy stays tentative: "likely", "about", "~".

extension SavingsStats {
    /// Rough parking spend across confirmed sessions — rates are estimates,
    /// so this is always presented with "~".
    static func estimatedSpendAED(sessions: [Session]) -> Decimal {
        sessions.filter(\.userConfirmedPaid).reduce(Decimal(0)) { sum, session in
            sum + Decimal(session.durationHours)
                * Decimal(ParkinRules.estimatedRateAED(zone: session.zoneCode, kind: session.zoneKind))
        }
    }
}

func formatAED(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).intValue.formatted()
}

private func kindColor(_ kind: InterventionKind) -> Color {
    switch kind {
    case .morningFreeToPaid: return Color(hex: 0xF5A623)
    case .unpaidNag: return Color(hex: 0xEE5A2B)
    case .expiryWarning: return Color(hex: 0xFF5168)
    }
}

// MARK: - Compact card (Home)

struct SavingsCardView: View {
    let totals: SavingsTotals
    let spendAED: Decimal
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("Reminders that likely saved you a fine: \(totals.likelySaves)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.labelTertiary)
                            .padding(4)
                    }
                }
            }
            Text("about AED \(formatAED(totals.avoidedAED)) avoided")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.labelSecondary)
            Text("Paid ~AED \(formatAED(spendAED)) in parking · likely avoided ~AED \(formatAED(totals.avoidedAED)) in fines")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.labelTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
    }
}

// MARK: - The dashboard: "Savings Pass over The Lot" — banknote edition

/// Single light appearance (user decision: no dark theme).
/// Banknote-green ticket, orange fleet, warm cream page, charcoal asphalt.
struct SavingsTheme {
    let page: Color, pageText: Color, secCap: Color
    let ticketA: Color, ticketB: Color, ticketC: Color
    let asphaltA: Color, asphaltB: Color, paint: Color
    let carTones: [(Color, Color, Color)]
    let glassA: Color, glassB: Color
    let warn: Color
    let stub: Color, stubText: Color, stubDash: Color
    let plus: Color, minus: Color, punchBG: Color, punchText: Color

    static let light = SavingsTheme(
        page: Color(hex: 0xF0EBE1), pageText: Color(hex: 0x23180F), secCap: Color(hex: 0x9A8D7A),
        ticketA: Color(hex: 0xFB4E2A), ticketB: Color(hex: 0xFF6E3C), ticketC: Color(hex: 0xFF5168),
        asphaltA: Color(hex: 0x3F4045), asphaltB: Color(hex: 0x37383C), paint: Color(hex: 0xE9E7DF),
        carTones: [
            (Color(hex: 0x34B37E), Color(hex: 0x19A373), Color(hex: 0x0E7D57)),
            (Color(hex: 0x4CC08D), Color(hex: 0x26AC7C), Color(hex: 0x128A61)),
            (Color(hex: 0x23A876), Color(hex: 0x0F8A5F), Color(hex: 0x0A6B49)),
        ],
        glassA: Color(hex: 0x2C2214), glassB: Color(hex: 0x1A130A),
        warn: Color(hex: 0xF2B23A),
        stub: .white, stubText: Color(hex: 0x23180F), stubDash: Color(hex: 0xE6DDCD),
        plus: Color(hex: 0x0F8A5F), minus: Color(hex: 0xB23A12),
        punchBG: Color(hex: 0xD9EEE2), punchText: Color(hex: 0x0D7A54))
}

/// One month-bay of the year lot: a parked car means no fine that month;
/// future months sit as empty dotted bays.
private struct MonthBay {
    let label: String
    let fined: Bool
    let future: Bool
    let tone: Int
}

/// Presentation scaffolding: a made-up year for the demo. To be re-wired to
/// the real ledger (month-grouped) before release.
private enum DemoYear {
    static let bays: [MonthBay] = [
        MonthBay(label: "JAN", fined: false, future: false, tone: 0),
        MonthBay(label: "FEB", fined: false, future: false, tone: 1),
        MonthBay(label: "MAR", fined: true,  future: false, tone: 0),
        MonthBay(label: "APR", fined: false, future: false, tone: 2),
        MonthBay(label: "MAY", fined: false, future: false, tone: 0),
        MonthBay(label: "JUN", fined: false, future: false, tone: 1),
        MonthBay(label: "JUL", fined: false, future: false, tone: 2),
        MonthBay(label: "AUG", fined: false, future: false, tone: 0),
        MonthBay(label: "SEP", fined: false, future: true,  tone: 0),
        MonthBay(label: "OCT", fined: false, future: true,  tone: 1),
        MonthBay(label: "NOV", fined: false, future: true,  tone: 2),
        MonthBay(label: "DEC", fined: false, future: true,  tone: 0),
    ]

    /// (punch, title, amount, negative) — 6–8 generated rows per completed
    /// month; future months are empty.
    static let receipts: [[(String, String, String, Bool)]] = {
        let zones = ["318C", "334B", "382F", "248W", "365A", "112D"]
        let templates = [
            "Paid Zone %@ before charging began",
            "Paid Zone %@ after the nag",
            "Extended Zone %@ before it lapsed",
        ]
        let counts = [4, 3, 5, 3, 4, 5, 3, 3, 0, 0, 0, 0]  // 30 saves = ~AED 4,500
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                      "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        var all: [[(String, String, String, Bool)]] = []
        for month in 0..<12 {
            var rows: [(String, String, String, Bool)] = []
            for i in 0..<counts[month] {
                let zone = zones[(month + i * 2) % zones.count]
                let title = String(format: templates[(month + i) % templates.count], zone)
                let day = 1 + i * 3 + (month % 3)
                rows.append(("\(day) \(months[month])", title, "+150", false))
            }
            if month == 2, rows.count >= 3 {
                rows.insert(("21 MAR", "One fine got through", "−150", true), at: 2)
            }
            all.append(rows)
        }
        return all
    }()

    static let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
}

struct SavingsLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \InterventionEvent.firedAt, order: .reverse) private var events: [InterventionEvent]

    @State private var carsParked = false
    /// Selected month bay (0 = January); nil = collapsed. Tapping the
    /// selected month again puts the light out and folds the receipts away.
    @State private var selectedMonth: Int? = 7
    /// Hero count-up: rolls from 0 to the real total on appear; instant
    /// under Reduce Motion.
    @State private var displayedAED = Decimal(0)

    private let theme = SavingsTheme.light

    private var saves: [InterventionEvent] { events.filter(\.decisive) }
    private var totals: SavingsTotals { SavingsStats.totals(in: modelContext) }
    private var spend: Decimal { SavingsStats.estimatedSpendAED(sessions: sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TicketHero(theme: theme, totals: totals, spend: spend,
                           displayedAED: displayedAED)
                    .padding(.top, 6)

                sectionCap("Your year · tap a month")
                LotView(theme: theme, bays: DemoYear.bays, selected: selectedMonth,
                        parked: carsParked, reduceMotion: reduceMotion) { index in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedMonth = (selectedMonth == index) ? nil : index
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                if let month = selectedMonth {
                    sectionCap("Torn off — \(DemoYear.monthNames[month]) receipts")
                    receiptsCard(forMonth: month)
                }

                sectionCap("Where it came from — literally")
                StreetMapCard()

                sectionCap("The app had your back")
                activityCard()

                Text("Estimates from the reminder ledger — likely, never certain.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secCap)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Savings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.pageText)
            }
        }
        .onAppear {
            carsParked = true
            if reduceMotion {
                displayedAED = totals.avoidedAED
            } else {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.95)) {
                    displayedAED = totals.avoidedAED
                }
            }
        }
        .onChange(of: totals.avoidedAED) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.9)) {
                displayedAED = totals.avoidedAED
            }
        }
    }

    /// Matches the app's section labels: 13pt semibold, sentence case.
    private func sectionCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secCap)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 9)
    }

    private func receiptsCard(forMonth month: Int) -> some View {
        let rows = DemoYear.receipts[month]
        return StubCard(theme: theme) {
            if rows.isEmpty {
                Text("Nothing here yet — \(DemoYear.monthNames[month]) is still ahead.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secCap)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { DashedRule(color: theme.stubDash) }
                    if row.3 {
                        KerbStrip(text: "\(row.0) · FINE GOT THROUGH · \(row.2)")
                            .padding(.vertical, 9)
                    } else {
                        StubRow(theme: theme, punch: row.0, text: row.1,
                                amount: row.2, negative: false)
                    }
                }
            }
        }
        .id(month) // fresh transition per month
        .transition(.opacity)
    }

    /// "The app had your back" as a signage tally: stencil labels with dotted
    /// leader lines running to painted counts.
    private func activityCard() -> some View {
        let counts = ActivityLog.counts(in: modelContext)
        let items: [(String, ActivityKind)] = [
            ("Parkin hand-offs", .parkinOpened),
            ("SMS payments", .smsPayStarted),
            ("False triggers caught", .notParkingDismissed),
            ("Quiet at Home and Office", .quietArrival),
            ("Free-spot arrivals", .freeArrival),
        ].filter { (counts[$0.1] ?? 0) > 0 }
        return AsphaltCard(theme: theme) {
            VStack(spacing: 13) {
                ForEach(items, id: \.0) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.0.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(theme.paint.opacity(0.85))
                            .layoutPriority(1)
                        DashedRule(color: theme.paint.opacity(0.25), thickness: 1.5)
                            .offset(y: -2)
                        Text("\(counts[item.1] ?? 0)")
                            .font(.system(size: 16, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(theme.paint)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    private func receiptTitle(for event: InterventionEvent) -> String {
        let zone = event.zoneCode.isEmpty ? "paid zone" : "Zone \(event.zoneCode)"
        switch event.kind {
        case .morningFreeToPaid: return "Paid \(zone) before charging began"
        case .unpaidNag: return "Paid \(zone) after the nag"
        case .expiryWarning: return "Extended \(zone) before it lapsed"
        }
    }
}

// MARK: - UAE map — "Where it came from", literally (W2, v2)

/// Demo pins for the presentation; re-wire to ledger zone data before release.
private struct MapCallout {
    let title: String
    let sub: String
    let color: Color
    let tagX: CGFloat, tagY: CGFloat      // callout box position
    let dotX: CGFloat, dotY: CGFloat      // anchor near Dubai
}

private struct StreetMapCard: View {
    private let callouts: [MapCallout] = [
        MapCallout(title: "318C · Karama", sub: "~1,800 · 12 saves",
                   color: Color(hex: 0xD6431A), tagX: 0.30, tagY: 0.10, dotX: 0.745, dotY: 0.235),
        MapCallout(title: "382F · Al Sufouh", sub: "~1,350 · 9 saves",
                   color: Color(hex: 0xC07F10), tagX: 0.22, tagY: 0.38, dotX: 0.72, dotY: 0.26),
        MapCallout(title: "365A · Al Qouz", sub: "~1,350 · 9 saves",
                   color: Color(hex: 0xE23350), tagX: 0.40, tagY: 0.66, dotX: 0.75, dotY: 0.285),
        MapCallout(title: "334B", sub: "−150 · the fine",
                   color: Color(hex: 0xB23A12), tagX: 0.84, tagY: 0.60, dotX: 0.775, dotY: 0.255),
    ]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                // the Gulf
                Color(hex: 0xD5E2DF)
                Text("THE GULF")
                    .font(.system(size: 10, weight: .semibold))
                    .italic()
                    .kerning(2)
                    .foregroundStyle(Color(hex: 0x93ACA8))
                    .position(x: width * 0.30, y: height * 0.30)

                // the country
                UAEShape()
                    .fill(Color(hex: 0xEDE3C9))
                UAEShape()
                    .stroke(Color(hex: 0xC9BC9C), lineWidth: 1.5)

                // city anchors
                Circle().fill(Color(hex: 0x9A8D7A)).frame(width: 5, height: 5)
                    .position(x: width * 0.59, y: height * 0.47)
                Text("ABU DHABI")
                    .font(.system(size: 7.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Color(hex: 0x9A8D7A))
                    .position(x: width * 0.59, y: height * 0.525)
                Text("DUBAI")
                    .font(.system(size: 8.5, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(Color(hex: 0x6d6455))
                    .position(x: width * 0.815, y: height * 0.31)

                // leader lines
                ForEach(callouts.indices, id: \.self) { index in
                    let callout = callouts[index]
                    Path { path in
                        path.move(to: CGPoint(x: width * callout.tagX, y: height * callout.tagY))
                        path.addLine(to: CGPoint(x: width * callout.dotX, y: height * callout.dotY))
                    }
                    .stroke(callout.color.opacity(0.55), lineWidth: 1.5)
                }

                // save dots clustered on Dubai
                ForEach(callouts.indices, id: \.self) { index in
                    let callout = callouts[index]
                    Circle()
                        .fill(callout.color)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .position(x: width * callout.dotX, y: height * callout.dotY)
                }

                // callout tags
                ForEach(callouts.indices, id: \.self) { index in
                    let callout = callouts[index]
                    VStack(alignment: .leading, spacing: 1) {
                        Text(callout.title)
                            .font(.system(size: 10.5, weight: .heavy))
                        Text(callout.sub)
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.92)
                    }
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(callout.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                    .position(x: width * callout.tagX, y: height * callout.tagY)
                }

                Text("HOME · 48 QUIET")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(Color(hex: 0x857A68))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(hex: 0xF0EBE1).opacity(0.9),
                                in: RoundedRectangle(cornerRadius: 6))
                    .position(x: width * 0.30, y: height * 0.88)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Map of the UAE with savings pinned at Dubai: Karama about 1,800, Al Sufouh about 1,350, Al Qouz about 1,350, and the fine at 334B")
    }
}

/// A simplified UAE silhouette — Gulf coast up to the Musandam horn, east
/// coast down past Fujairah, straight desert borders. Hand-traced, no SDK.
private struct UAEShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.03, 0.57), (0.14, 0.60), (0.24, 0.56), (0.34, 0.545),
            (0.44, 0.51), (0.52, 0.50), (0.59, 0.47), (0.66, 0.40),
            (0.72, 0.31), (0.76, 0.24), (0.79, 0.19), (0.85, 0.135),
            (0.89, 0.10), (0.94, 0.05), (0.97, 0.03),
            (0.98, 0.14), (0.97, 0.28), (0.91, 0.34), (0.89, 0.53),
            (0.85, 0.54), (0.82, 0.97), (0.55, 0.945), (0.22, 0.93),
            (0.02, 0.63),
        ]
        var path = Path()
        path.move(to: CGPoint(x: rect.width * points[0].0, y: rect.height * points[0].1))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.width * point.0, y: rect.height * point.1))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Asphalt panels (sections drawn in the lot's own material)

private struct AsphaltCard<Content: View>: View {
    let theme: SavingsTheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    LinearGradient(colors: [theme.asphaltA, theme.asphaltB],
                                   startPoint: .top, endPoint: .bottom)
                    Ellipse().fill(.black.opacity(0.14))
                        .frame(width: 80, height: 40).offset(x: 80, y: -30)
                    Ellipse().fill(.black.opacity(0.10))
                        .frame(width: 60, height: 30).offset(x: -90, y: 40)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Yellow-black hazard kerb with a stencil label — the fine's road furniture.
private struct KerbStrip: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .kerning(1)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x17140E))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Color(hex: 0xF2B23A).opacity(0.95),
                            in: RoundedRectangle(cornerRadius: 5))
            Spacer()
        }
        .padding(.vertical, 7)
        .background(HazardStripes().fill(Color(hex: 0xF2B23A).opacity(0.85))
            .background(Color(hex: 0x17140E)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Diagonal hazard stripes, deterministic.
private struct HazardStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stripeWidth: CGFloat = 14
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height + stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: rect.maxY))
            path.closeSubpath()
            x += stripeWidth * 2
        }
        return path
    }
}

// MARK: - Ticket hero (banknote green, split-flap amount)

private struct TicketHero: View {
    let theme: SavingsTheme
    let totals: SavingsTotals
    let spend: Decimal
    let displayedAED: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("YALLA PARK")
                Spacer()
                Text("SAVINGS PASS")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .kerning(0.5)
            .opacity(0.95)

            Text("~AED \(formatAED(displayedAED))")
                .font(.system(size: 52, weight: .heavy))
                .kerning(-1)
                .monospacedDigit()
                .padding(.top, 11)
                .contentTransition(.numericText(value: NSDecimalNumber(decimal: displayedAED).doubleValue))
                .accessibilityLabel("About \(formatAED(totals.avoidedAED)) dirhams in fines likely avoided")

            Text("in fines, likely avoided · \(totals.likelySaves) save\(totals.likelySaves == 1 ? "" : "s")")
                .font(.system(size: 13.5, weight: .medium))
                .opacity(0.93)
                .padding(.top, 10)

            DashedRule(color: .white.opacity(0.42), thickness: 2)
                .padding(.vertical, 12)

            HStack {
                Text("PARKING SPEND ~\(formatAED(spend))")
                Spacer()
                Text(roiText)
            }
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.4)
            .opacity(0.95)
            .monospacedDigit()

            Barcode()
                .frame(height: 34)
                .padding(.top, 12)
                .opacity(0.92)
        }
        .foregroundStyle(.white)
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [theme.ticketA, theme.ticketB, theme.ticketC],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(alignment: .topLeading) { notch.offset(x: -13, y: 110) }
        .overlay(alignment: .topTrailing) { notch.offset(x: 13, y: 110) }
    }

    private var notch: some View {
        Circle().fill(theme.page).frame(width: 26, height: 26)
    }

    private var roiText: String {
        guard spend > 0, totals.avoidedAED > 0 else { return "RETURN —" }
        let multiple = NSDecimalNumber(decimal: totals.avoidedAED).doubleValue
            / NSDecimalNumber(decimal: spend).doubleValue
        return "RETURN ≈\(String(format: "%.0f", multiple))×"
    }
}

/// Fixed pseudo-random bar pattern — same every render, looks like a barcode.
private struct Barcode: View {
    private let widths: [CGFloat] = [2,3,1,2,1,3,2,1,1,2,3,1,2,2,1,3,1,1,2,1,3,2,1,2,1,1,3,2,1,2,3,1,1,2,1,2,3,1,2,1,2,1,3,1,1,2,2,1,3,1,2,1,1,3,2,1,2,1,3,2,1,1,2,3,1,2,1,2,3,1,1,2,1,3,2,1,2,1,1,2]
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(widths.indices, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white : .clear)
                        .frame(width: widths[index] * geo.size.width / widths.reduce(0, +))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Horizontal dashed rule (ticket perforation / receipt separators).
struct DashedRule: View {
    var color: Color
    var thickness: CGFloat = 1.5
    var body: some View {
        LineShape()
            .stroke(color, style: StrokeStyle(lineWidth: thickness, dash: [5, 5]))
            .frame(height: thickness)
    }
    private struct LineShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}

// MARK: - The Lot (the year: one bay per month)

private struct LotView: View {
    let theme: SavingsTheme
    let bays: [MonthBay]
    let selected: Int?
    let parked: Bool
    let reduceMotion: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            bayRow(0..<6, facingDown: true)
            driveLane
            bayRow(6..<12, facingDown: false)
            footer
        }
        .padding(11)
        .background(
            ZStack {
                LinearGradient(colors: [theme.asphaltA, theme.asphaltB],
                               startPoint: .top, endPoint: .bottom)
                Ellipse().fill(.black.opacity(0.16)).frame(width: 90, height: 46).offset(x: -70, y: -60)
                Ellipse().fill(.black.opacity(0.12)).frame(width: 66, height: 34).offset(x: 90, y: 70)
                Text("P")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(theme.paint.opacity(0.05))
                    .offset(x: 120, y: 78)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func bayRow(_ range: Range<Int>, facingDown: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(range, id: \.self) { index in
                BayCell(theme: theme, bay: bays[index], facingDown: facingDown,
                        selected: index == selected,
                        jitter: jitter(index),
                        delay: Double(index) * 0.05,
                        parked: parked, reduceMotion: reduceMotion)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
                    .accessibilityLabel("\(DemoYear.monthNames[index]), \(bays[index].fined ? "fine that month" : "fine-free")")
                    .accessibilityAddTraits(index == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: 100)
    }

    private func jitter(_ index: Int) -> Double {
        index.isMultiple(of: 3) ? 1.8 : (index.isMultiple(of: 2) ? -1.6 : 0.6)
    }

    private var driveLane: some View {
        HStack {
            Text("→")
            Spacer()
            Text("TAP A MONTH")
                .kerning(2)
            Spacer()
            Text("→")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.paint.opacity(0.8))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            DashedRule(color: theme.paint.opacity(0.5), thickness: 2)
                .padding(.horizontal, 5)
        )
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(LinearGradient(colors: [theme.carTones[0].0, theme.carTones[0].2],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 16)
                Text("fine-free month")
            }
            Spacer()
            HStack(spacing: 5) {
                Text("✕").font(.system(size: 12, weight: .black)).foregroundStyle(theme.warn)
                Text("fine that month")
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.paint.opacity(0.8))
        .padding(.horizontal, 4)
        .padding(.top, 9)
        .padding(.bottom, 2)
    }
}

private struct BayCell: View {
    let theme: SavingsTheme
    let bay: MonthBay
    let facingDown: Bool
    let selected: Bool
    let jitter: Double
    let delay: Double
    let parked: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if selected {
                // The lot lamp: a soft, rounded pool of warm light kept
                // inside the bay's own lines.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0xF2B23A).opacity(0.62),
                                                  Color(hex: 0xDF9B22).opacity(0.24),
                                                  .clear],
                                         center: .center, startRadius: 4, endRadius: 56))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            }
            HStack {
                bayLine
                Spacer()
                bayLine
            }
            VStack(spacing: 3) {
                if facingDown { monthLabel }
                Spacer(minLength: 0)
                cell
                Spacer(minLength: 0)
                if !facingDown { monthLabel }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var bayLine: some View {
        LinearGradient(colors: facingDown
                       ? [theme.paint.opacity(selected ? 1 : 0.85), theme.paint.opacity(selected ? 1 : 0.85), .clear]
                       : [.clear, theme.paint.opacity(selected ? 1 : 0.85), theme.paint.opacity(selected ? 1 : 0.85)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: selected ? 3 : 2)
            .clipShape(Capsule())
    }

    private var monthLabel: some View {
        Text(bay.label)
            .font(.system(size: 8, weight: selected ? .heavy : .bold))
            .kerning(1)
            .foregroundStyle(selected ? Color(hex: 0xF2B23A) : theme.paint.opacity(0.65))
    }

    @ViewBuilder
    private var cell: some View {
        if bay.future {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(theme.paint.opacity(0.45),
                              style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: 27, height: 48)
                .opacity(0.6)
        } else if bay.fined {
            VStack(spacing: 2) {
                Text("✕")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(theme.warn)
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
                Text("FINE")
                    .font(.system(size: 7.5, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(theme.warn.opacity(0.8))
            }
        } else {
            CarView(theme: theme, tone: bay.tone)
                .rotationEffect(.degrees((facingDown ? 180 : 0) + jitter))
                .scaleEffect(parked || reduceMotion ? 1 : 0.2)
                .opacity(parked || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? nil
                           : .spring(response: 0.5, dampingFraction: 0.72).delay(delay),
                           value: parked)
        }
    }
}

/// Top-down car: body, windshield, roof gloss, rear glass, mirrors, headlights.
private struct CarView: View {
    let theme: SavingsTheme
    let tone: Int

    var body: some View {
        let tones = theme.carTones[tone % theme.carTones.count]
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tones.0, tones.1, tones.2],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
                        .blendMode(.overlay)
                )
            VStack(spacing: 0) {
                HStack {
                    lamp; Spacer(); lamp
                }
                .padding(.horizontal, 3.5)
                .padding(.top, 2)
                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 5,
                                       bottomTrailingRadius: 5, topTrailingRadius: 3)
                    .fill(LinearGradient(colors: [theme.glassA, theme.glassB],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 9)
                    .padding(.horizontal, 3.5)
                    .padding(.top, 2.5)
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 15)
                    .padding(.horizontal, 4)
                    .padding(.top, 1.5)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.glassB.opacity(0.55))
                    .frame(height: 6)
                    .padding(.horizontal, 4.5)
                    .padding(.bottom, 4)
            }
        }
        .frame(width: 31, height: 56)
        .overlay(alignment: .topLeading) { mirror.offset(x: -3.5, y: 12) }
        .overlay(alignment: .topTrailing) { mirror.offset(x: 3.5, y: 12) }
        .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
    }

    private var lamp: some View {
        Capsule().fill(Color(hex: 0xFFE9B8).opacity(0.8)).frame(width: 6, height: 2.5)
    }

    private var mirror: some View {
        let tones = theme.carTones[tone % theme.carTones.count]
        return RoundedRectangle(cornerRadius: 2.5).fill(tones.1).frame(width: 4, height: 7)
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
    }
}

// MARK: - Receipt stubs

private struct StubCard<Content: View>: View {
    let theme: SavingsTheme
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.stub, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StubRow: View {
    let theme: SavingsTheme
    let punch: String
    let text: String
    let amount: String
    let negative: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(punch)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(negative ? theme.minus : theme.punchText)
                .frame(minWidth: 38)
                .frame(height: 23)
                .background(negative ? theme.minus.opacity(0.15) : theme.punchBG,
                            in: RoundedRectangle(cornerRadius: 6))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.stubText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(negative ? theme.minus : theme.plus)
        }
        .padding(.vertical, 11)
    }
}
