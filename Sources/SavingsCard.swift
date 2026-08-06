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

/// One cell of the car park.
private enum BayContent {
    case car(tone: Int, month: String)
    case fine(month: String)
    case next
}

struct SavingsLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \InterventionEvent.firedAt, order: .reverse) private var events: [InterventionEvent]

    @State private var carsParked = false
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

                sectionCap("Six months · one bay per save")
                LotView(theme: theme, bays: bayContents(), bestMonth: bestMonthLabel(),
                        parked: carsParked, reduceMotion: reduceMotion)

                sectionCap("Torn off — your receipts")
                receiptsCard()

                sectionCap("Where it came from")
                sourcesCard()

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

    /// Saves + reported fines, chronological, capped at 11 bays + a NEXT slot.
    private func bayContents() -> [BayContent] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var seenFineSessions = Set<UUID>()
        var dated: [(Date, BayContent)] = []
        for (index, event) in saves.sorted(by: { ($0.resolvedAt ?? $0.firedAt) < ($1.resolvedAt ?? $1.firedAt) }).enumerated() {
            let date = event.resolvedAt ?? event.firedAt
            dated.append((date, .car(tone: index % 3, month: formatter.string(from: date).uppercased())))
        }
        for event in events where event.outcome == .gotFined && event.reportedFineAED != nil {
            let key = event.relatedSessionID ?? event.id
            guard seenFineSessions.insert(key).inserted else { continue }
            let date = event.finedAt ?? event.firedAt
            dated.append((date, .fine(month: formatter.string(from: date).uppercased())))
        }
        var bays = dated.sorted { $0.0 < $1.0 }.suffix(11).map(\.1)
        if bays.count < 12 { bays.append(.next) }
        return bays
    }

    private func bestMonthLabel() -> String? {
        let monthly = SavingsStats.monthlySaves(events: events)
        guard let best = monthly.max(by: { $0.savedAED < $1.savedAED }), best.savedAED > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: best.month).uppercased()
    }

    private func receiptsCard() -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return StubCard(theme: theme) {
            if saves.isEmpty {
                Text("No saves yet — counting starts the first time a reminder catches a fine for you.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secCap)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(saves.prefix(8).enumerated()), id: \.element.id) { index, event in
                    if index > 0 { DashedRule(color: theme.stubDash) }
                    StubRow(theme: theme,
                            punch: formatter.string(from: event.firedAt).uppercased(),
                            text: receiptTitle(for: event),
                            amount: "+\(formatAED(event.estimatedFineAvoidedAED))",
                            negative: false)
                }
                if totals.finesReported > 0 {
                    DashedRule(color: theme.stubDash)
                    StubRow(theme: theme, punch: "✕",
                            text: "One fine got through",
                            amount: "−\(formatAED(totals.finesReportedAED))",
                            negative: true)
                }
            }
        }
    }

    private func sourcesCard() -> some View {
        let breakdown = SavingsStats.savesByKind(events: events)
        let maxAED = breakdown.map(\.savedAED).max() ?? 1
        return StubCard(theme: theme) {
            ForEach(Array(breakdown.enumerated()), id: \.element.kind) { index, entry in
                if index > 0 { DashedRule(color: theme.stubDash) }
                HStack(spacing: 12) {
                    iconTile(entry.kind.icon, kindColor(entry.kind))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.kind.displayLabel)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.stubText)
                            Spacer()
                            Text("~AED \(formatAED(entry.savedAED))")
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.stubText)
                        }
                        GeometryReader { geo in
                            let ratio = maxAED > 0
                                ? NSDecimalNumber(decimal: entry.savedAED).doubleValue
                                    / NSDecimalNumber(decimal: maxAED).doubleValue
                                : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.stubDash.opacity(0.6))
                                Capsule().fill(kindColor(entry.kind))
                                    .frame(width: max(6, geo.size.width * ratio))
                            }
                        }
                        .frame(height: 4.5)
                    }
                }
                .padding(.vertical, 11)
            }
            if totals.finesReported > 0 {
                DashedRule(color: theme.stubDash)
                HStack(spacing: 12) {
                    iconTile("exclamationmark.triangle.fill", Color(hex: 0xE8912B))
                    Text("Fines that got through")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.stubText)
                    Spacer()
                    Text("AED \(formatAED(totals.finesReportedAED))")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0xE8912B))
                }
                .padding(.vertical, 11)
            }
        }
    }

    private func activityCard() -> some View {
        let counts = ActivityLog.counts(in: modelContext)
        let items: [(String, String, ActivityKind)] = [
            ("arrow.up.forward.app.fill", "Parkin hand-offs", .parkinOpened),
            ("message.fill", "SMS payments", .smsPayStarted),
            ("hand.raised.fill", "False triggers caught", .notParkingDismissed),
            ("house.fill", "Quiet at Home and Office", .quietArrival),
            ("checkmark.circle.fill", "Free-spot arrivals", .freeArrival),
        ].filter { (counts[$0.2] ?? 0) > 0 }
        return StubCard(theme: theme) {
            ForEach(Array(items.enumerated()), id: \.element.1) { index, item in
                if index > 0 { DashedRule(color: theme.stubDash) }
                HStack(spacing: 12) {
                    iconTile(item.0, Color(hex: 0xEE5A2B))
                    Text(item.1)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.stubText)
                    Spacer()
                    Text("\(counts[item.2] ?? 0)")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.stubText.opacity(0.55))
                }
                .padding(.vertical, 11)
            }
        }
    }

    private func iconTile(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

// MARK: - The Lot

private struct LotView: View {
    let theme: SavingsTheme
    let bays: [BayContent]
    let bestMonth: String?
    let parked: Bool
    let reduceMotion: Bool

    var body: some View {
        let rowSize = 6
        let topRow = Array(bays.prefix(rowSize))
        let bottomRow = Array(bays.dropFirst(rowSize).prefix(rowSize))
        VStack(spacing: 0) {
            bayRow(topRow, facingDown: true, indexOffset: 0)
            driveLane
            if !bottomRow.isEmpty {
                bayRow(bottomRow, facingDown: false, indexOffset: rowSize)
            }
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

    private func bayRow(_ row: [BayContent], facingDown: Bool, indexOffset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, content in
                BayCell(theme: theme, content: content, facingDown: facingDown,
                        jitter: jitter(indexOffset + index),
                        delay: Double(indexOffset + index) * 0.07,
                        parked: parked, reduceMotion: reduceMotion)
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
            Text("+\(formatAED(ParkinRules.assumedFineAED)) EACH")
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
                Text("save +150")
            }
            Spacer()
            HStack(spacing: 5) {
                Text("✕").font(.system(size: 12, weight: .black)).foregroundStyle(theme.warn)
                Text("fine −150")
            }
            Spacer()
            Text(bestMonth.map { "best · \($0)" } ?? "")
                .opacity(0.65)
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
    let content: BayContent
    let facingDown: Bool
    let jitter: Double
    let delay: Double
    let parked: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
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
                       ? [theme.paint.opacity(0.85), theme.paint.opacity(0.85), .clear]
                       : [.clear, theme.paint.opacity(0.85), theme.paint.opacity(0.85)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 2)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var monthLabel: some View {
        switch content {
        case .car(_, let month), .fine(let month):
            Text(month)
                .font(.system(size: 8, weight: .bold))
                .kerning(1)
                .foregroundStyle(theme.paint.opacity(0.65))
        case .next:
            Text(" ").font(.system(size: 8, weight: .bold))
        }
    }

    @ViewBuilder
    private var cell: some View {
        switch content {
        case .car(let tone, _):
            CarView(theme: theme, tone: tone)
                .rotationEffect(.degrees((facingDown ? 180 : 0) + jitter))
                .scaleEffect(parked || reduceMotion ? 1 : 0.2)
                .opacity(parked || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? nil
                           : .spring(response: 0.5, dampingFraction: 0.72).delay(delay),
                           value: parked)
        case .fine:
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
        case .next:
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.paint.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 27, height: 48)
                Text("NEXT")
                    .font(.system(size: 7.5, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(theme.paint.opacity(0.55))
            }
            .opacity(0.6)
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
