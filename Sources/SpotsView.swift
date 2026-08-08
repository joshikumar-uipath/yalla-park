import SwiftUI
import SwiftData

/// My Spots: two segments. TICKETS — every session as a ticket in the app's
/// own stub language (live coral mini-pass for the active one, torn-off stub
/// rows for the past; Parkin's tickets screen was the inspiration, not the
/// design). SPOTS — the remembered places, unchanged.
struct SpotsView: View {
    @Query(sort: \Spot.lastParkedAt, order: .reverse) private var spots: [Spot]
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var interventions: [InterventionEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var segment = 0
    @State private var passSession: Session?
    @State private var fineTarget: Session?
    @State private var fineAmountText = ""

    private var activeSessions: [Session] { sessions.filter(\.isActive) }
    private var pastSessions: [Session] { sessions.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $segment) {
                    Text("Tickets").tag(0)
                    Text("Spots").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 2)

                if segment == 0 { ticketsList } else { spotsList }
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
            // The full pass — same screen as Home's, with extend on board.
            .sheet(item: $passSession) { session in
                PassScreen(session: session, onClose: { passSession = nil })
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Tickets

    @ViewBuilder
    private var ticketsList: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No tickets yet",
                systemImage: "ticket",
                description: Text("Pay once from the map and your ticket lives here — live countdown while it runs, stub for the record after.")
            )
        } else {
            List {
                if !activeSessions.isEmpty {
                    Section {
                        ForEach(activeSessions) { session in
                            ActiveTicketCard(session: session) { passSession = session }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                        }
                    } header: {
                        Text("Active now")
                    }
                }
                if !pastSessions.isEmpty {
                    Section {
                        ForEach(pastSessions.prefix(50)) { session in
                            pastTicketRow(session)
                        }
                    } header: {
                        Text("Torn off — past tickets")
                    } footer: {
                        Text("Got a fine anyway? Swipe a ticket and tell us — it keeps the savings numbers honest.")
                    }
                }
            }
        }
    }

    /// One past session as a receipt stub: day punch, zone, times, rough fee.
    private func pastTicketRow(_ session: Session) -> some View {
        HStack(spacing: 10) {
            Text(session.startedAt.formatted(.dateTime.day().month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(hex: 0x0D7A54))
                .frame(minWidth: 46)
                .frame(height: 23)
                .background(Color(hex: 0xD9EEE2), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(zoneLabel(session.zoneCode, operator: session.parkingOperator))
                        .font(.system(size: 15.5, weight: .semibold))
                    if sessionFined(session) {
                        Text("Fined")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.vertical, 2).padding(.horizontal, 7)
                            .background(Color(hex: 0xFDE5E0), in: Capsule())
                            .foregroundStyle(Theme.coral)
                    }
                }
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened))–\(session.expiresAt.formatted(date: .omitted, time: .shortened)) · \(session.durationHours)h\(session.extendedCount > 0 ? " · extended ×\(session.extendedCount)" : "")")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.labelSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let fee = feeEstimate(session) {
                    Text("~AED \(fee)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.labelPrimary)
                }
                Text(session.paidViaParkinApp
                     ? "Parkin app"
                     : (session.parkingOperator == .parkin ? "SMS 7275" : session.parkingOperator.label))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.labelTertiary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !sessionFined(session) {
                Button("I got fined") {
                    fineAmountText = "\(session.parkingOperator.assumedFineAED)"
                    fineTarget = session
                }
                .tint(.orange)
            }
        }
    }

    /// Rough spend for the stub's corner — estimates only, so "~".
    private func feeEstimate(_ session: Session) -> Int? {
        switch session.parkingOperator {
        case .parkin:
            return session.durationHours
                * ParkinRules.estimatedRateAED(zone: session.zoneCode, kind: session.zoneKind)
        case .parkonic:
            return nil // unpublished tariffs — never guess
        default:
            return session.parkingOperator.estimatedRateAED(zone: session.zoneCode)
                .map { $0 * session.durationHours }
        }
    }

    // MARK: - Spots (unchanged list, its own segment)

    @ViewBuilder
    private var spotsList: some View {
        if spots.isEmpty {
            ContentUnavailableView(
                "No spots yet",
                systemImage: "mappin.slash",
                description: Text("Park somewhere and pay once — the zone is remembered and auto-filled next time.")
            )
        } else {
            List {
                Section("Remembered places") {
                    ForEach(spots) { spot in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(spot.name)
                                    .font(.system(size: 16, weight: .semibold))
                                if let designation = spot.designation {
                                    Label(designation.label, systemImage: designation.icon)
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.vertical, 2).padding(.horizontal, 7)
                                        .background(Color(hex: 0xEFEDE7), in: Capsule())
                                        .foregroundStyle(Theme.labelSecondary)
                                }
                            }
                            HStack(spacing: 6) {
                                Text(spot.zoneKind == .free ? "Free parking" : "Zone \(spot.zoneCode)")
                                Text("·")
                                Text("parked \(spot.timesParked)×")
                                Text("·")
                                Text(spot.lastParkedAt.formatted(.relative(presentation: .named)))
                            }
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.labelSecondary)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            ForEach(SpotDesignation.allCases, id: \.self) { designation in
                                if spot.designation != designation {
                                    Button {
                                        spot.designation = designation
                                    } label: {
                                        Label("Mark as \(designation.label) — never remind here",
                                              systemImage: designation.icon)
                                    }
                                }
                            }
                            if spot.designation != nil {
                                Button {
                                    spot.designation = nil
                                } label: {
                                    Label("Remove designation", systemImage: "bell.fill")
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { modelContext.delete(spots[index]) }
                    }
                }
            }
        }
    }

    // MARK: - Fine reporting

    private var fineAlertShown: Binding<Bool> {
        Binding(get: { fineTarget != nil },
                set: { if !$0 { fineTarget = nil } })
    }

    private func sessionFined(_ session: Session) -> Bool {
        interventions.contains { $0.relatedSessionID == session.id && $0.outcome == .gotFined }
    }

    private func submitFine() {
        guard let session = fineTarget else { return }
        let amount = Decimal(string: fineAmountText) ?? session.parkingOperator.assumedFineAED
        InterventionLog.reportFine(sessionID: session.id, amountAED: amount, in: modelContext)
        fineTarget = nil
    }
}

// MARK: - Active ticket (coral mini-pass)

/// The running session as a slim version of the Savings Pass — same coral,
/// same perforation, live countdown. Tap anywhere to open the full pass.
private struct ActiveTicketCard: View {
    let session: Session
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YALLA PARK")
                    Spacer()
                    Text(zoneLabel(session.zoneCode, operator: session.parkingOperator).uppercased())
                }
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.5)
                .opacity(0.95)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, session.expiresAt.timeIntervalSince(context.date))
                    Text(Self.countdown(remaining))
                        .font(.system(size: 40, weight: .heavy))
                        .monospacedDigit()
                        .kerning(-0.5)
                        .padding(.top, 9)
                }

                Text("remaining · expires \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12.5, weight: .medium))
                    .opacity(0.93)
                    .padding(.top, 2)

                DashedRule(color: .white.opacity(0.42), thickness: 2)
                    .padding(.vertical, 11)

                HStack {
                    Text(session.plate.uppercased())
                        .monospacedDigit()
                    Spacer()
                    Text("Open pass →")
                }
                .font(.system(size: 12.5, weight: .bold))
                .kerning(0.4)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(colors: [Theme.coral, Color(hex: 0xFF6E3C), Color(hex: 0xFF5168)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Active ticket, tap to open the pass")
    }

    private static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
