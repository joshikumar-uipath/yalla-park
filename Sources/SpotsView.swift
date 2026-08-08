import SwiftUI
import SwiftData

/// My Spots: ONE list — places, with their tickets inside. Each spot row
/// expands to its tickets (live coral mini-pass first, then expired stubs);
/// collapsed, a small green ticket badge on the right says "paid & active
/// here right now". Sessions in zones without a saved spot gather under
/// "Other tickets".
struct SpotsView: View {
    @Query(sort: \Spot.lastParkedAt, order: .reverse) private var spots: [Spot]
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var interventions: [InterventionEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var expandedSpots: Set<UUID> = []
    @State private var otherExpanded = false
    @State private var passSession: Session?
    @State private var fineTarget: Session?
    @State private var fineAmountText = ""

    /// Sessions belonging to a spot — matched by zone code.
    private func spotSessions(_ spot: Spot) -> [Session] {
        guard !spot.zoneCode.isEmpty else { return [] }
        return sessions.filter { $0.zoneCode == spot.zoneCode }
    }

    /// Sessions whose zone has no saved spot (deleted spots, Parkin-app
    /// payments with no zone).
    private var orphanSessions: [Session] {
        let knownZones = Set(spots.map(\.zoneCode).filter { !$0.isEmpty })
        return sessions.filter { $0.zoneCode.isEmpty || !knownZones.contains($0.zoneCode) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty && sessions.isEmpty {
                    ContentUnavailableView(
                        "No spots yet",
                        systemImage: "mappin.slash",
                        description: Text("Park somewhere and pay once — the place is remembered here, with every ticket tucked inside it.")
                    )
                } else {
                    List {
                        if !spots.isEmpty {
                            Section {
                                ForEach(spots) { spot in
                                    spotGroup(spot)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet { modelContext.delete(spots[index]) }
                                }
                            } header: {
                                Text("My Spots")
                            } footer: {
                                Text("Tap a spot for its tickets. Got a fine anyway? Swipe a ticket and tell us — it keeps the savings numbers honest.")
                            }
                        }
                        if !orphanSessions.isEmpty {
                            Section {
                                otherTicketsGroup
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
            .sheet(item: $passSession) { session in
                PassScreen(session: session, onClose: { passSession = nil })
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Spot row (expandable)

    private func spotGroup(_ spot: Spot) -> some View {
        let tickets = spotSessions(spot)
        let active = tickets.filter(\.isActive)
        let past = tickets.filter { !$0.isActive }
        return DisclosureGroup(isExpanded: expandedBinding(for: spot.id)) {
            if tickets.isEmpty {
                Text("No tickets here yet.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.labelTertiary)
            }
            ForEach(active) { session in
                ActiveTicketCard(session: session) { passSession = session }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
            }
            ForEach(past.prefix(20)) { session in
                pastTicketRow(session)
            }
        } label: {
            spotLabel(spot, hasActiveTicket: !active.isEmpty)
        }
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

    private func spotLabel(_ spot: Spot, hasActiveTicket: Bool) -> some View {
        HStack(spacing: 10) {
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
            Spacer(minLength: 6)
            if hasActiveTicket {
                // The "paid & running here" badge — a small live ticket.
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Theme.success, in: Capsule())
                    .accessibilityLabel("Active ticket here")
            }
        }
        .padding(.vertical, 2)
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { expandedSpots.contains(id) },
                set: { open in
                    if open { expandedSpots.insert(id) } else { expandedSpots.remove(id) }
                })
    }

    // MARK: - Other tickets (no saved spot)

    private var otherTicketsGroup: some View {
        let active = orphanSessions.filter(\.isActive)
        let past = orphanSessions.filter { !$0.isActive }
        return DisclosureGroup(isExpanded: $otherExpanded) {
            ForEach(active) { session in
                ActiveTicketCard(session: session) { passSession = session }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
            }
            ForEach(past.prefix(20)) { session in
                pastTicketRow(session)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Other tickets")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Zones without a saved spot")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.labelSecondary)
                }
                Spacer(minLength: 6)
                if !active.isEmpty {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Theme.success, in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Ticket rows

    /// A finished session as a torn-off stub, stamped expired.
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
                        .font(.system(size: 15, weight: .semibold))
                    if sessionFined(session) {
                        Text("Fined")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.vertical, 2).padding(.horizontal, 7)
                            .background(Color(hex: 0xFDE5E0), in: Capsule())
                            .foregroundStyle(Theme.coral)
                    }
                }
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.durationHours)h\(session.extendedCount > 0 ? " · extended ×\(session.extendedCount)" : "")")
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
                Text("Expired \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
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
