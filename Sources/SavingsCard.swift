import SwiftUI
import SwiftData
import Charts

/// Task 3 — the savings surface. Every number on these views traces to a
/// decisive InterventionEvent visible in the ledger below; no multipliers.
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

// MARK: - Compact card (Home + top of the stats screen)

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

func formatAED(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).intValue.formatted()
}

// MARK: - Ledger screen (Settings ▸ Savings)

struct SavingsLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \InterventionEvent.firedAt, order: .reverse) private var events: [InterventionEvent]

    private var saves: [InterventionEvent] { events.filter(\.decisive) }
    private var totals: SavingsTotals { SavingsStats.totals(in: modelContext) }

    var body: some View {
        List {
            Section {
                SavingsCardView(totals: totals,
                                spendAED: SavingsStats.estimatedSpendAED(sessions: sessions))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            tilesSection
            monthlyChartSection
            savesByKindSection
            activitySection

            if saves.isEmpty {
                Section {
                    Text("No saves yet — we'll start counting the first time a reminder catches a fine for you.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.labelSecondary)
                }
            } else {
                Section("Receipts") {
                    ForEach(saves) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.firedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.labelTertiary)
                            Text(receiptText(for: event))
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Theme.labelPrimary)
                            Text("~AED \(formatAED(event.estimatedFineAvoidedAED)) fine likely avoided")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.success)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Savings")
    }

    // MARK: Summary tiles

    private var tilesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile("\(totals.likelySaves)", "fines likely dodged")
                statTile("~\(formatAED(totals.avoidedAED))", "AED likely avoided")
                statTile("\(sessions.filter(\.userConfirmedPaid).count)", "sessions paid")
                statTile("~\(formatAED(SavingsStats.estimatedSpendAED(sessions: sessions)))",
                         "AED spent parking")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func statTile(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.labelPrimary)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
    }

    // MARK: Monthly ledger chart (stacked by save type)

    @ViewBuilder
    private var monthlyChartSection: some View {
        let slices = SavingsStats.monthlyKindSaves(events: events)
        if slices.contains(where: { $0.savedAED > 0 }) {
            Section {
                Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
                    BarMark(
                        x: .value("Month", slice.month, unit: .month),
                        y: .value("AED", NSDecimalNumber(decimal: slice.savedAED).doubleValue)
                    )
                    .foregroundStyle(by: .value("Type", slice.kind.displayLabel))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale([
                    InterventionKind.morningFreeToPaid.displayLabel: Color(hex: 0xFF9A54),
                    InterventionKind.unpaidNag.displayLabel: Theme.coral,
                    InterventionKind.expiryWarning.displayLabel: Color(hex: 0xFF5168),
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                    }
                }
                .frame(height: 160)
                .padding(.vertical, 6)
            } header: {
                Text("Likely avoided, by month")
            } footer: {
                Text("~AED per month from the receipts below — estimates, never certainties.")
            }
        }
    }

    // MARK: Where the saves came from (types of savings)

    @ViewBuilder
    private var savesByKindSection: some View {
        let breakdown = SavingsStats.savesByKind(events: events)
        if !breakdown.isEmpty || totals.finesReported > 0 {
            Section {
                ForEach(breakdown, id: \.kind) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.kind.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                            .frame(width: 22)
                        Text(entry.kind.displayLabel)
                            .font(.system(size: 14.5, weight: .medium))
                        Spacer()
                        Text("\(entry.saves)× · ~AED \(formatAED(entry.savedAED))")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.labelPrimary)
                    }
                }
                if totals.finesReported > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        Text("Fines that got through")
                            .font(.system(size: 14.5, weight: .medium))
                        Spacer()
                        Text("\(totals.finesReported)× · AED \(formatAED(totals.finesReportedAED))")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Where the saves came from")
            } footer: {
                Text("Each defense layer, with what it likely caught — and, honestly, what slipped past.")
            }
        }
    }

    // MARK: Everything else the app caught

    @ViewBuilder
    private var activitySection: some View {
        let counts = ActivityLog.counts(in: modelContext)
        if !counts.isEmpty {
            Section {
                activityRow("arrow.up.forward.app.fill", "Handed off to the Parkin app",
                            counts[.parkinOpened])
                activityRow("message.fill", "SMS payments started", counts[.smsPayStarted])
                activityRow("hand.raised.fill", "False triggers dismissed",
                            counts[.notParkingDismissed])
                activityRow("house.fill", "Quiet arrivals at Home/Office",
                            counts[.quietArrival])
                activityRow("checkmark.circle.fill", "Arrivals at your free spots",
                            counts[.freeArrival])
            } header: {
                Text("The app had your back")
            } footer: {
                Text("Activity, not money — the AED figures above only ever come from reminder-caused saves.")
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ icon: String, _ title: String, _ count: Int?) -> some View {
        if let count, count > 0 {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                Spacer()
                Text("\(count)×")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelPrimary)
            }
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
