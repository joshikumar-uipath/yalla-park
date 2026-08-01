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
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \InterventionEvent.firedAt, order: .reverse) private var events: [InterventionEvent]

    private var saves: [InterventionEvent] { events.filter(\.decisive) }
    private var totals: SavingsTotals { SavingsStats.totals(in: modelContext) }
    private var spend: Decimal { SavingsStats.estimatedSpendAED(sessions: sessions) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                monthlyChartCard
                breakdownCard
                activityCard
                receiptsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            LinearGradient(colors: [Theme.passCanvasTop, Theme.passCanvasBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("Savings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero — the number that earns the screenshot

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12, weight: .bold))
                    Text("LIKELY SAVED")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(1.4)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(.white.opacity(0.22), in: Capsule())

                Spacer()

                Text("\(totals.likelySaves) save\(totals.likelySaves == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 11)
                    .background(.white.opacity(0.22), in: Capsule())
            }

            Text("~AED \(formatAED(totals.avoidedAED))")
                .font(.system(size: 56, weight: .heavy))
                .kerning(-1.8)
                .padding(.top, 20)
                .contentTransition(.numericText())

            Text("in parking fines, likely avoided")
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.92)
                .padding(.top, 2)

            if spend > 0 && totals.avoidedAED > 0 {
                let multiple = NSDecimalNumber(decimal: totals.avoidedAED).doubleValue
                    / NSDecimalNumber(decimal: spend).doubleValue
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Paid ~AED \(formatAED(spend)) for parking — dodged ≈\(String(format: "%.0f", multiple))× that in fines")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .opacity(0.95)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.top, 18)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xFB4E2A), location: 0),
                        .init(color: Color(hex: 0xFF6E3C), location: 0.55),
                        .init(color: Color(hex: 0xFF5168), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [Color(hex: 0xFF9A54).opacity(0.9), .clear],
                               center: UnitPoint(x: 0.88, y: 0.02),
                               startRadius: 0, endRadius: 240)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 170, weight: .black))
                    .foregroundStyle(.white.opacity(0.05))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 110, y: 55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.sheetRadius, style: .continuous))
        .shadow(color: Theme.coral.opacity(0.35), radius: 22, y: 12)
    }

    // MARK: Monthly chart

    @ViewBuilder
    private var monthlyChartCard: some View {
        let slices = SavingsStats.monthlyKindSaves(events: events)
        let monthly = SavingsStats.monthlySaves(events: events)
        if slices.contains(where: { $0.savedAED > 0 }) {
            card {
                cardHeader("By month", icon: "chart.bar.fill")

                HStack(spacing: 12) {
                    ForEach(InterventionKind.allCases, id: \.self) { kind in
                        HStack(spacing: 5) {
                            Circle().fill(kindColor(kind)).frame(width: 7, height: 7)
                            Text(kind.displayLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.labelSecondary)
                        }
                    }
                }
                .padding(.top, 8)

                Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
                    BarMark(
                        x: .value("Month", slice.month, unit: .month),
                        y: .value("AED", NSDecimalNumber(decimal: slice.savedAED).doubleValue),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(kindColor(slice.kind))
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 170)
                .padding(.top, 12)

                if let best = monthly.max(by: { $0.savedAED < $1.savedAED }), best.savedAED > 0 {
                    Text("Best month: \(best.month.formatted(.dateTime.month(.wide))) · ~AED \(formatAED(best.savedAED))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .padding(.top, 10)
                }
            }
        }
    }

    // MARK: Where the saves came from

    @ViewBuilder
    private var breakdownCard: some View {
        let breakdown = SavingsStats.savesByKind(events: events)
        if !breakdown.isEmpty || totals.finesReported > 0 {
            card {
                cardHeader("Where the saves came from", icon: "square.stack.3d.up.fill")

                let maxAED = breakdown.map(\.savedAED).max() ?? 1
                VStack(spacing: 16) {
                    ForEach(breakdown, id: \.kind) { entry in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 11) {
                                ZStack {
                                    Circle()
                                        .fill(kindColor(entry.kind).opacity(0.14))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: entry.kind.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(kindColor(entry.kind))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.kind.displayLabel)
                                        .font(.system(size: 14.5, weight: .bold))
                                        .foregroundStyle(Theme.labelPrimary)
                                    Text("\(entry.saves) save\(entry.saves == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.labelSecondary)
                                }
                                Spacer()
                                Text("~AED \(formatAED(entry.savedAED))")
                                    .font(.system(size: 15, weight: .heavy))
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
                                    Capsule().fill(kindColor(entry.kind).gradient)
                                        .frame(width: max(8, geo.size.width * ratio))
                                }
                            }
                            .frame(height: 6)
                        }
                    }

                    if totals.finesReported > 0 {
                        HStack(spacing: 11) {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.14))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Fines that got through")
                                    .font(.system(size: 14.5, weight: .bold))
                                    .foregroundStyle(Theme.labelPrimary)
                                Text("we count our misses too")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.labelSecondary)
                            }
                            Spacer()
                            Text("AED \(formatAED(totals.finesReportedAED))")
                                .font(.system(size: 15, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    // MARK: Activity

    @ViewBuilder
    private var activityCard: some View {
        let counts = ActivityLog.counts(in: modelContext)
        if !counts.isEmpty {
            card {
                cardHeader("The app had your back", icon: "hand.raised.fill")

                let items: [(String, String, ActivityKind)] = [
                    ("arrow.up.forward.app.fill", "Parkin hand-offs", .parkinOpened),
                    ("message.fill", "SMS payments", .smsPayStarted),
                    ("hand.raised.fill", "False triggers caught", .notParkingDismissed),
                    ("house.fill", "Quiet at Home/Office", .quietArrival),
                    ("checkmark.circle.fill", "Free-spot arrivals", .freeArrival),
                ]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(items.filter { (counts[$0.2] ?? 0) > 0 }, id: \.1) { icon, title, kind in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.coral)
                                Spacer()
                            }
                            Text("\(counts[kind] ?? 0)×")
                                .font(.system(size: 24, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Theme.labelPrimary)
                            Text(title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.labelSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.passCanvasTop,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
                .padding(.top, 12)

                Text("Activity is counted, never priced — the AED above comes only from reminder-caused saves.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.labelTertiary)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Receipts timeline

    @ViewBuilder
    private var receiptsCard: some View {
        card {
            cardHeader("Receipts", icon: "list.bullet.rectangle.fill")

            if saves.isEmpty {
                Text("No saves yet — we'll start counting the first time a reminder catches a fine for you.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.labelSecondary)
                    .padding(.top, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(saves.prefix(10).enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(kindColor(event.kind))
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                if index < min(saves.count, 10) - 1 {
                                    Rectangle()
                                        .fill(Theme.segmentedTrack)
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.firedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()).uppercased())
                                    .font(.system(size: 10.5, weight: .heavy))
                                    .kerning(0.6)
                                    .foregroundStyle(Theme.labelTertiary)
                                Text(receiptText(for: event))
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Theme.labelPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("~AED \(formatAED(event.estimatedFineAvoidedAED)) likely avoided")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.success)
                            }
                            .padding(.bottom, 16)
                            Spacer(minLength: 0)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: Card chrome

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func cardHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.coral)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(Theme.labelPrimary)
        }
    }

    private func receiptText(for event: InterventionEvent) -> String {
        let zone = event.zoneCode.isEmpty ? "a paid zone" : "Zone \(event.zoneCode)"
        let acted = event.resolvedAt?.formatted(date: .omitted, time: .shortened) ?? "—"
        switch event.kind {
        case .morningFreeToPaid:
            return "Reminded you before \(zone) started charging · you paid at \(acted)"
        case .unpaidNag:
            return "Nagged you after parking unpaid in \(zone) · you paid at \(acted)"
        case .expiryWarning:
            return "Warned you before \(zone) expired · you extended at \(acted)"
        }
    }
}
