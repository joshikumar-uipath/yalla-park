import SwiftUI
import SwiftData

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
