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
    case .unpaidNag: return Theme.coral
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

// MARK: - The dashboard

struct SavingsLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \InterventionEvent.firedAt, order: .reverse) private var events: [InterventionEvent]

    /// Hero count-up: rolls from 0 to the real total on appear (numericText),
    /// lands instantly when Reduce Motion is on.
    @State private var displayedAED = Decimal(0)

    private var saves: [InterventionEvent] { events.filter(\.decisive) }
    private var totals: SavingsTotals { SavingsStats.totals(in: modelContext) }
    private var spend: Decimal { SavingsStats.estimatedSpendAED(sessions: sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.top, 4)

                section("By month") { monthlyChartCard }
                section("Where it came from") { sourcesCard }
                section("The app had your back") { activityCard }
                section("Receipts") { receiptsCard }

                Text("Figures are estimates from the reminder ledger — likely, never certain.")
                    .font(.footnote)
                    .foregroundStyle(Theme.labelTertiary)
                    .padding(.top, 22)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Theme.passCanvasTop.ignoresSafeArea())
        .navigationTitle("Savings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
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

    // MARK: Section chrome — labels live OUTSIDE the cards (Health-style),
    // cards are flat insets: white, continuous 16pt radius, no shadows.

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.labelSecondary)
                .padding(.horizontal, 4)
            content()
        }
        .padding(.top, 26)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func iconTile(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var hairline: some View {
        Rectangle().fill(Theme.segmentedTrack).frame(height: 0.7)
            .padding(.leading, 40)
    }

    // MARK: Hero — one Wallet-style moment; everything after it stays quiet.

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Text("P")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.25),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Yalla Park")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("\(totals.likelySaves) likely save\(totals.likelySaves == 1 ? "" : "s")")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.9)
            }

            Text("~AED \(formatAED(displayedAED))")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .kerning(-0.5)
                .padding(.top, 26)
                .contentTransition(.numericText(value: NSDecimalNumber(decimal: displayedAED).doubleValue))
                .accessibilityLabel("About \(formatAED(totals.avoidedAED)) dirhams in fines likely avoided")

            Text("in fines, likely avoided")
                .font(.subheadline.weight(.medium))
                .opacity(0.9)
                .padding(.top, 2)

            if spend > 0 && totals.avoidedAED > 0 {
                Rectangle().fill(.white.opacity(0.25)).frame(height: 0.7)
                    .padding(.vertical, 14)
                let multiple = NSDecimalNumber(decimal: totals.avoidedAED).doubleValue
                    / NSDecimalNumber(decimal: spend).doubleValue
                Text("Parking cost ~AED \(formatAED(spend)) · avoided ≈\(String(format: "%.0f", multiple))× that")
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xF64C22), location: 0),
                    .init(color: Color(hex: 0xFB5E3A), location: 0.6),
                    .init(color: Color(hex: 0xF74E5A), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    // MARK: Chart

    private var monthlyChartCard: some View {
        let slices = SavingsStats.monthlyKindSaves(events: events)
        let monthly = SavingsStats.monthlySaves(events: events)
        return card {
            Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
                BarMark(
                    x: .value("Month", slice.month, unit: .month),
                    y: .value("AED", NSDecimalNumber(decimal: slice.savedAED).doubleValue),
                    width: .ratio(0.45)
                )
                .foregroundStyle(kindColor(slice.kind))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.labelTertiary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .accessibilityLabel("Bar chart of dirhams likely avoided per month, split by reminder type")

            HStack(spacing: 14) {
                ForEach(InterventionKind.allCases, id: \.self) { kind in
                    HStack(spacing: 5) {
                        Circle().fill(kindColor(kind)).frame(width: 6, height: 6)
                        Text(kind.displayLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }
                Spacer()
                if monthly.count >= 2,
                   monthly[monthly.count - 1].savedAED > monthly[monthly.count - 2].savedAED {
                    Label("Up", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.success)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: Sources

    private var sourcesCard: some View {
        let breakdown = SavingsStats.savesByKind(events: events)
        let maxAED = breakdown.map(\.savedAED).max() ?? 1
        return card {
            VStack(spacing: 0) {
                ForEach(Array(breakdown.enumerated()), id: \.element.kind) { index, entry in
                    if index > 0 { hairline.padding(.vertical, 11) }
                    HStack(spacing: 12) {
                        iconTile(entry.kind.icon, kindColor(entry.kind))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.kind.displayLabel)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.labelPrimary)
                                Spacer()
                                Text("~AED \(formatAED(entry.savedAED))")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.labelPrimary)
                            }
                            GeometryReader { geo in
                                let ratio = maxAED > 0
                                    ? NSDecimalNumber(decimal: entry.savedAED).doubleValue
                                        / NSDecimalNumber(decimal: maxAED).doubleValue
                                    : 0
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.segmentedTrack)
                                    Capsule().fill(kindColor(entry.kind))
                                        .frame(width: max(6, geo.size.width * ratio))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }

                if totals.finesReported > 0 {
                    hairline.padding(.vertical, 11)
                    HStack(spacing: 12) {
                        iconTile("exclamationmark.triangle.fill", .orange)
                        Text("Fines that got through")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.labelPrimary)
                        Spacer()
                        Text("AED \(formatAED(totals.finesReportedAED))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: Activity

    private var activityCard: some View {
        let counts = ActivityLog.counts(in: modelContext)
        let items: [(String, String, ActivityKind)] = [
            ("arrow.up.forward.app.fill", "Parkin hand-offs", .parkinOpened),
            ("message.fill", "SMS payments", .smsPayStarted),
            ("hand.raised.fill", "False triggers caught", .notParkingDismissed),
            ("house.fill", "Quiet at Home and Office", .quietArrival),
            ("checkmark.circle.fill", "Free-spot arrivals", .freeArrival),
        ].filter { (counts[$0.2] ?? 0) > 0 }
        return card {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.1) { index, item in
                    if index > 0 { hairline.padding(.vertical, 11) }
                    HStack(spacing: 12) {
                        iconTile(item.0, Theme.coral)
                        Text(item.1)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.labelPrimary)
                        Spacer()
                        Text("\(counts[item.2] ?? 0)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }
            }
        }
    }

    // MARK: Receipts — Wallet-transaction rows

    private var receiptsCard: some View {
        card {
            if saves.isEmpty {
                Text("No saves yet — counting starts the first time a reminder catches a fine for you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(saves.prefix(8).enumerated()), id: \.element.id) { index, event in
                        if index > 0 { hairline.padding(.vertical, 11) }
                        HStack(spacing: 12) {
                            iconTile(event.kind.icon, kindColor(event.kind))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receiptTitle(for: event))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.labelPrimary)
                                Text(event.firedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                    .font(.caption)
                                    .foregroundStyle(Theme.labelSecondary)
                            }
                            Spacer()
                            Text("+\(formatAED(event.estimatedFineAvoidedAED))")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.success)
                        }
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
