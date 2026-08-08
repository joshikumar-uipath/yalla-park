import SwiftUI
import SwiftData

/// My Spots: ONE feed, newest first. Active tickets sit at the very top as
/// live coral cards (tap → pass). Below, everything in reverse-chronological
/// order: each spot with its expired tickets INLINE right under it, and
/// tickets whose spot is gone shown as plain stubs in the same stream —
/// nothing hidden behind a tap, no separate sections.
struct SpotsView: View {
    @Query(sort: \Spot.lastParkedAt, order: .reverse) private var spots: [Spot]
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var interventions: [InterventionEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var passSession: Session?
    /// The one ticket currently unfolded inline (slide-down). Tapping any
    /// other row moves it there; tapping the same row or the open ticket
    /// collapses it.
    @State private var expandedTicketID: UUID?
    @State private var fineTarget: Session?
    @State private var fineAmountText = ""

    private var activeSessions: [Session] { sessions.filter(\.isActive) }

    /// One card per feed position: a spot with its expired tickets, or a
    /// ZONE gathering the tickets whose spot no longer exists — loose stubs
    /// never float contextless between other people's cards.
    private enum FeedEntry: Identifiable {
        case spotBlock(Spot, [Session])
        case zoneBlock(String, [Session])

        var id: String {
            switch self {
            case .spotBlock(let spot, _): return spot.id.uuidString
            case .zoneBlock(let zone, _): return "zone-\(zone)"
            }
        }
        var sortDate: Date {
            switch self {
            case .spotBlock(let spot, let tickets):
                return max(spot.lastParkedAt, tickets.first?.startedAt ?? .distantPast)
            case .zoneBlock(_, let tickets):
                return tickets.first?.startedAt ?? .distantPast
            }
        }
    }

    /// Expired tickets claimed by spots (zone match, first spot wins); the
    /// rest group by zone into their own cards.
    private var feed: [FeedEntry] {
        let past = sessions.filter { !$0.isActive }
        var claimed = Set<UUID>()
        var entries: [FeedEntry] = spots.map { spot in
            guard !spot.zoneCode.isEmpty else { return .spotBlock(spot, []) }
            let tickets = past.filter { $0.zoneCode == spot.zoneCode && !claimed.contains($0.id) }
            tickets.forEach { claimed.insert($0.id) }
            return .spotBlock(spot, tickets)
        }
        let loose = past.filter { !claimed.contains($0.id) }
        let grouped = Dictionary(grouping: loose, by: \.zoneCode)
        entries += grouped.map { zone, tickets in
            .zoneBlock(zone, tickets.sorted { $0.startedAt > $1.startedAt })
        }
        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    /// "Zone 318C" → the community it names, for meaningful loose-zone cards.
    private func communityName(forZone zone: String) -> String? {
        guard let number = Int(zone.prefix(while: \.isNumber)) else { return nil }
        return ZoneLocator.communities.first { $0.number == number }?.displayName
    }

    /// The header strip: what this page holds, in one quiet line.
    private var summaryLine: String {
        let ticketCount = sessions.count
        let placeCount = spots.count
        let spend = sessions.compactMap(feeEstimate).reduce(0, +)
        var parts: [String] = []
        if placeCount > 0 { parts.append("\(placeCount) place\(placeCount == 1 ? "" : "s")") }
        if ticketCount > 0 { parts.append("\(ticketCount) ticket\(ticketCount == 1 ? "" : "s")") }
        if spend > 0 { parts.append("~AED \(spend) in parking") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty && sessions.isEmpty {
                    ContentUnavailableView(
                        "No spots yet",
                        systemImage: "mappin.slash",
                        description: Text("Park somewhere and pay once — the place and its tickets live here.")
                    )
                } else {
                    List {
                        // What this page holds, at a glance.
                        Section {
                            Text(summaryLine)
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.labelSecondary)
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                        ForEach(activeSessions) { session in
                            Section {
                                ActiveTicketCard(session: session) { passSession = session }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                        }
                        // One CARD per place — its tickets live inside it.
                        ForEach(feed) { entry in
                            Section {
                                switch entry {
                                case .spotBlock(let spot, let tickets):
                                    spotRow(spot)
                                    if let live = activeSession(at: spot),
                                       expandedTicketID == live.id {
                                        inlineActiveTicket(live)
                                    }
                                    ForEach(tickets.prefix(10)) { session in
                                        pastTicketRow(session, showZone: false)
                                        if expandedTicketID == session.id {
                                            inlineExpiredTicket(session)
                                        }
                                    }
                                case .zoneBlock(let zone, let tickets):
                                    zoneHeaderRow(zone)
                                    ForEach(tickets.prefix(10)) { session in
                                        pastTicketRow(session, showZone: false)
                                        if expandedTicketID == session.id {
                                            inlineExpiredTicket(session)
                                        }
                                    }
                                }
                            }
                        }
                        Section {
                        } footer: {
                            Text("Got a fine anyway? Swipe a ticket and tell us — it keeps the savings numbers honest.")
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

    // MARK: - Zone card header (tickets whose spot is gone)

    private func zoneHeaderRow(_ zone: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(zone.isEmpty ? "Via the Parkin app" : "Zone \(zone)")
                .font(.system(size: 16, weight: .semibold))
            Text(zone.isEmpty
                 ? "Tickets paid in Parkin's own app"
                 : (communityName(forZone: zone).map { "\($0) · no saved spot" } ?? "No saved spot"))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.labelSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Spot row

    /// The live ticket at this spot, if any — powers the badge and row tap.
    private func activeSession(at spot: Spot) -> Session? {
        guard !spot.zoneCode.isEmpty else { return nil }
        return activeSessions.first { $0.zoneCode == spot.zoneCode }
    }

    private func spotRow(_ spot: Spot) -> some View {
        let liveTicket = activeSession(at: spot)
        return HStack(spacing: 10) {
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
                // Meta line skips what it doesn't know — never a dangling "Zone ·".
                Text(spotMeta(spot))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.labelSecondary)
            }
            Spacer(minLength: 6)
            if liveTicket != nil {
                // Paid & running here — tap the row to open the pass.
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Theme.success, in: Capsule())
                    .accessibilityLabel("Active ticket here")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let liveTicket else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedTicketID = expandedTicketID == liveTicket.id ? nil : liveTicket.id
            }
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Forget spot", role: .destructive) {
                modelContext.delete(spot)
            }
        }
    }

    private func spotMeta(_ spot: Spot) -> String {
        var parts: [String] = []
        if spot.zoneKind == .free {
            parts.append("Free parking")
        } else if !spot.zoneCode.isEmpty {
            parts.append("Zone \(spot.zoneCode)")
        }
        parts.append("parked \(spot.timesParked)×")
        parts.append(spot.lastParkedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    // MARK: - Ticket stubs

    /// A finished session as a torn-off stub, stamped expired. Zone is
    /// omitted inside its own card (the card header already says it).
    private func pastTicketRow(_ session: Session, showZone: Bool) -> some View {
        HStack(spacing: 10) {
            Text(session.startedAt.formatted(.dateTime.day().month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(hex: 0x0D7A54))
                .frame(minWidth: 46)
                .frame(height: 23)
                .background(Color(hex: 0xD9EEE2), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(showZone
                         ? zoneLabel(session.zoneCode, operator: session.parkingOperator)
                         : "\(session.startedAt.formatted(date: .omitted, time: .shortened)) – \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                    if sessionFined(session) {
                        Text("Fined")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.vertical, 2).padding(.horizontal, 7)
                            .background(Color(hex: 0xFDE5E0), in: Capsule())
                            .foregroundStyle(Theme.coral)
                    }
                }
                Text("\(session.durationHours) hour\(session.durationHours == 1 ? "" : "s")\(session.extendedCount > 0 ? " · extended ×\(session.extendedCount)" : "")\(session.paidViaParkinApp ? " · Parkin app" : "")")
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedTicketID = expandedTicketID == session.id ? nil : session.id
            }
        }
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

// MARK: - Inline ticket rows

extension SpotsView {
    /// The coral live ticket, unfolded under its spot row. Tapping the card
    /// opens the full pass; the row above collapses it.
    @ViewBuilder
    func inlineActiveTicket(_ session: Session) -> some View {
        ActiveTicketCard(session: session) { passSession = session }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
    }

    /// The grey expired ticket, unfolded under its stub. Tap it (or the
    /// stub) to fold it back up.
    @ViewBuilder
    func inlineExpiredTicket(_ session: Session) -> some View {
        ExpiredTicketCard(session: session, feeAED: feeEstimate(session))
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedTicketID = nil
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
    }
}

// MARK: - Expired ticket card (the same pass, greyed out)

/// A finished session in the exact shape of the live pass — but drained of
/// color: warm-grey gradient, frozen 0:00:00, EXPIRED stamp.
struct ExpiredTicketCard: View {
    let session: Session
    let feeAED: Int?

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YALLA PARK")
                    Spacer()
                    Text(zoneLabel(session.zoneCode, operator: session.parkingOperator).uppercased())
                }
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.5)
                .opacity(0.9)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("0:00:00")
                        .font(.system(size: 40, weight: .heavy))
                        .monospacedDigit()
                        .kerning(-0.5)
                    Text("EXPIRED")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1.5)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                        .rotationEffect(.degrees(-4))
                }
                .padding(.top, 9)

                Text("ran \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) – \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12.5, weight: .medium))
                    .opacity(0.9)
                    .padding(.top, 2)

                DashedRule(color: .white.opacity(0.38), thickness: 2)
                    .padding(.vertical, 11)

                HStack {
                    Text(session.plate.uppercased())
                        .monospacedDigit()
                    Spacer()
                    Text("\(session.durationHours)h\(session.extendedCount > 0 ? " · extended ×\(session.extendedCount)" : "")\(feeAED.map { " · ~AED \($0)" } ?? "")")
                        .monospacedDigit()
                }
                .font(.system(size: 12.5, weight: .bold))
                .kerning(0.4)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(colors: [Color(hex: 0x8E8A84), Color(hex: 0x76726C), Color(hex: 0x635F5A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
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
