import SwiftUI
import SwiftData

struct SpotsView: View {
    @Query(sort: \Spot.lastParkedAt, order: .reverse) private var spots: [Spot]
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var interventions: [InterventionEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var fineTarget: Session?
    @State private var fineAmountText = ""

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty && sessions.isEmpty {
                    ContentUnavailableView(
                        "No spots yet",
                        systemImage: "mappin.slash",
                        description: Text("Park somewhere and pay once — the zone is remembered and auto-filled next time.")
                    )
                } else {
                    List {
                        if !spots.isEmpty {
                            Section("My Spots") {
                                ForEach(spots) { spot in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(spot.name)
                                            .font(.system(size: 16, weight: .semibold))
                                        HStack(spacing: 6) {
                                            Text("Zone \(spot.zoneCode)")
                                            Text("·")
                                            Text("parked \(spot.timesParked)×")
                                            Text("·")
                                            Text(spot.lastParkedAt.formatted(.relative(presentation: .named)))
                                        }
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(Theme.labelSecondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet { modelContext.delete(spots[index]) }
                                }
                            }
                        }

                        if !sessions.isEmpty {
                            Section {
                                ForEach(sessions.prefix(50)) { session in
                                    sessionRow(session)
                                }
                            } header: {
                                Text("History")
                            } footer: {
                                Text("Got a fine anyway? Swipe a session and tell us — it keeps the savings numbers honest.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Spots")
            .alert("Report a fine", isPresented: fineAlertShown) {
                TextField("Amount (AED)", text: $fineAmountText)
                    .keyboardType(.numberPad)
                Button("Report fine", role: .destructive) { submitFine() }
                Button("Cancel", role: .cancel) { fineTarget = nil }
            } message: {
                Text("This removes any \"likely saved\" credit for this session, so the ledger never overstates.")
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Zone \(session.zoneCode)")
                    .font(.system(size: 16, weight: .semibold))
                if sessionFined(session) {
                    Text("Fined")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(Color(hex: 0xFDE5E0), in: Capsule())
                        .foregroundStyle(Theme.coral)
                }
            }
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.durationHours)h\(session.extendedCount > 0 ? " (+\(session.extendedCount) extend)" : "")")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.labelSecondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !sessionFined(session) {
                Button("I got fined") {
                    fineAmountText = "\(ParkinRules.assumedFineAED)"
                    fineTarget = session
                }
                .tint(.orange)
            }
        }
    }

    private var fineAlertShown: Binding<Bool> {
        Binding(get: { fineTarget != nil },
                set: { if !$0 { fineTarget = nil } })
    }

    private func sessionFined(_ session: Session) -> Bool {
        interventions.contains { $0.relatedSessionID == session.id && $0.outcome == .gotFined }
    }

    private func submitFine() {
        guard let session = fineTarget else { return }
        let amount = Decimal(string: fineAmountText) ?? ParkinRules.assumedFineAED
        InterventionLog.reportFine(sessionID: session.id, amountAED: amount, in: modelContext)
        fineTarget = nil
    }
}
