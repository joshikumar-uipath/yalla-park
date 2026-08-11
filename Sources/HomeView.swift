import SwiftUI
import MapKit
import SwiftData

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var spots: [Spot]

    @AppStorage("plate") private var plate = ""
    @AppStorage("plateEmirate") private var plateEmirate = Emirate.dubai.rawValue
    @AppStorage("plateLetters") private var plateLetters = ""
    @AppStorage("plateNumber") private var plateNumber = ""
    @AppStorage("recentZones") private var recentZonesCSV = ""
    @AppStorage("debugForcePaid") private var debugForcePaid = false
    @AppStorage("mapSatellite") private var mapSatellite = false

    @State private var location = LocationService()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .alBarsha, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
    )

    @State private var zoneCode = ""
    @State private var zoneKind: ZoneKind = .standard
    /// Who takes this payment: Parkin (7275, community zones) or Parkonic
    /// (6670, P-zones). Set by spot memory or community lookup; user can flip.
    @State private var parkingOperator: ParkingOperator = .parkin
    /// User flipped the operator by hand — location fixes stop second-guessing.
    @State private var operatorOverridden = false
    @State private var matchedSpot: Spot?
    /// GPS-derived district → zone number suggestion (ZoneLocator).
    @State private var suggestedCommunity: Community?
    @State private var manualZoneEntry = false
    @State private var verdict: Verdict = ParkinRules.verdict(kind: .standard)
    @State private var hours = 1

    @State private var showComposer = false
    @State private var showConfirm = false
    /// The pass being viewed (item-driven so either of two active tickets
    /// can be opened).
    @State private var passTarget: Session?
    @State private var extending = false
    @State private var dismissed = false
    /// User chose "parking somewhere else" while a ticket runs — the sheet
    /// shows the pay flow for a SECOND parallel ticket.
    @State private var payingSecondTicket = false
    /// "I need to pay here today" at a Home/Office spot — one-visit override.
    @State private var payAnyway = false
    /// Waiting for the user to come back from the Parkin app.
    @State private var awaitingParkinReturn = false
    /// The pending payment is happening in the Parkin app, not by SMS.
    @State private var paidViaParkin = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showShortcutGuide = false
    @AppStorage("morningLeadMinutes") private var morningLeadMinutes = 15
    @AppStorage("defaultHours") private var defaultHours = 1
    @AppStorage("automationVerified") private var automationVerified = false
    @AppStorage("setupMarkedDone") private var setupMarkedDone = false
    /// Home savings card: dismiss hides it until the save count grows again.
    @AppStorage("savingsCardDismissedCount") private var savingsCardDismissedCount = 0
    @State private var showLedger = false
    @State private var showScanner = false
    /// Guard on the destructive "payment didn't go through" — field report:
    /// one stray tap deleted a live pass with 1:54 remaining.
    @State private var showVoidConfirm = false
    /// The last voided pass, kept until its own expiry so a mistaken void
    /// can be undone in place.
    @State private var voidedBackup: VoidedPass?
    @FocusState private var zoneFieldFocused: Bool

    /// Snapshot of a session at the moment it was voided — enough to rebuild
    /// it exactly if the void turns out to be a mis-tap.
    struct VoidedPass {
        let plate: String
        let zoneCode: String
        let kindRaw: String
        let operatorRaw: String?
        let startedAt: Date
        let durationHours: Int
        let extendedCount: Int
        let expiresAt: Date
    }

    private var activeSession: Session? { sessions.first(where: \.isActive) }
    private var activeSessions: [Session] { sessions.filter(\.isActive) }
    /// The ticket that runs out first — what the widget and chip track.
    private var soonestActiveSession: Session? {
        activeSessions.min(by: { $0.expiresAt < $1.expiresAt })
    }
    /// Which session an extend applies to: the one whose notification was
    /// tapped if known, else the sheet's displayed (most recent) session.
    private var extendTarget: Session? {
        if let id = NotificationManager.shared.extendTargetSessionID,
           let match = sessions.first(where: { $0.id == id && $0.isActive }) {
            return match
        }
        return activeSession
    }
    /// The matched Home/Office place, unless the user chose to pay here today.
    private var designatedSpot: Spot? {
        guard !payAnyway, let spot = matchedSpot, spot.designation != nil else { return nil }
        return spot
    }
    private var recentZones: [String] {
        recentZonesCSV.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
    private var rate: Int { ParkinRules.estimatedRateAED(zone: zoneCode, kind: zoneKind) }
    /// Hourly estimate for the sheet — nil hides the price (Parkonic).
    private var displayRate: Int? {
        switch parkingOperator {
        case .parkin: return rate
        default: return parkingOperator.estimatedRateAED(zone: zoneCode)
        }
    }
    private var plateProfile: PlateProfile {
        PlateProfile(emirate: Emirate(rawValue: plateEmirate) ?? .dubai,
                     letters: plateLetters, number: plateNumber)
    }
    private var smsBody: String {
        // Extends route by the SESSION's operator: reply-style operators get
        // their bare "Y"/"E"; resend-style get the full payment SMS again.
        if extending, let session = extendTarget {
            switch session.parkingOperator.extendMethod {
            case .reply(let reply):
                return reply
            case .resendPayment:
                return session.parkingOperator.smsBody(
                    plate: plateProfile, zone: session.zoneCode, hours: 1)
            }
        }
        return parkingOperator.smsBody(plate: plateProfile, zone: zoneCode, hours: hours)
    }
    private var smsRecipient: String {
        if extending, let session = extendTarget { return session.parkingOperator.smsNumber }
        return parkingOperator.smsNumber
    }
    /// The pay button needs a plate and whatever "zone" means here.
    private var canPay: Bool {
        guard !plate.isEmpty else { return false }
        switch parkingOperator.zoneStyle {
        case .community: return !zoneCode.isEmpty
        case .pZone: return ParkonicRules.isValidZone(zoneCode)
        case .tier: return ["S", "P"].contains(zoneCode.uppercased())
        case .none: return true
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            map
            locationPill
            VStack(spacing: 10) {
                if !automationVerified && !setupMarkedDone && activeSession == nil {
                    setupBanner
                }
                // Quiet ROI moment — only when nothing needs paying right now.
                if activeSession == nil && !verdict.paymentRequired {
                    let totals = SavingsStats.totals(in: modelContext)
                    if totals.likelySaves > savingsCardDismissedCount {
                        Button { showLedger = true } label: {
                            SavingsCardView(totals: totals,
                                            spendAED: SavingsStats.estimatedSpendAED(sessions: sessions),
                                            onDismiss: { savingsCardDismissedCount = totals.likelySaves })
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(.horizontal, 10)
                    }
                }
                sheet
            }
        }
        .sheet(isPresented: $showShortcutGuide) {
            OnboardingView(startAtShortcut: true) { showShortcutGuide = false }
        }
        .sheet(isPresented: $showLedger) {
            NavigationStack { SavingsLedgerView() }
        }
        .sheet(isPresented: $showScanner) {
            ZoneScannerSheet { code in
                zoneCode = code
                manualZoneEntry = false
                zoneFieldFocused = false
            }
        }
        .onAppear {
            runPipeline()
            // Screenshot/design-iteration hook.
            if CommandLine.arguments.contains("-showSavings") { showLedger = true }
        }
        .onChange(of: router.parkedTrigger) { runPipeline() }
        .onChange(of: router.extendTrigger) {
            guard let session = extendTarget else { return }
            extending = true
            if session.paidViaParkinApp { openParkinApp() } else { startComposerFlow() }
        }
        // Back from Parkin → the one honest question.
        .onChange(of: scenePhase) {
            if scenePhase == .active && awaitingParkinReturn {
                awaitingParkinReturn = false
                showConfirm = true
            }
        }
        .onChange(of: location.fixID) { handleLocationFix() }
        .sheet(isPresented: $showComposer, onDismiss: { showConfirm = true }) {
            MessageComposer(recipients: [smsRecipient], body: smsBody) {
                showComposer = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmPaidSheet(
                smsBody: smsBody,
                viaParkinApp: paidViaParkin,
                parkingOperator: extending
                    ? (extendTarget?.parkingOperator ?? parkingOperator)
                    : parkingOperator,
                onConfirm: confirmPaid,
                onNotYet: { showConfirm = false; paidViaParkin = false }
            )
        }
        // A sheet, not fullScreenCover, so the pass swipes away naturally;
        // "Back to map" stays as the discoverable path.
        .sheet(item: $passTarget) { session in
            PassScreen(session: session, onClose: { passTarget = nil })
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Map layer

    private var map: some View {
        Map(position: $camera) {
            if let coordinate = location.coordinate {
                Annotation("", coordinate: coordinate) {
                    CarPin(reduceMotion: reduceMotion)
                }
            }
        }
        .mapStyle(mapSatellite
                  ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
                  : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
        // Tap the map = put the keyboard away.
        .simultaneousGesture(TapGesture().onEnded { zoneFieldFocused = false })
    }

    private var locationPill: some View {
        VStack {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                    Text(location.areaName ?? "Locating…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.labelPrimary)
                        .lineLimit(1)
                    Text("· just now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.labelSecondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                Spacer(minLength: 8)
                savingsPill
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Always-visible route back to a live pass (field request: after
            // any detour, the ticket must stay one tap away).
            if let session = soonestActiveSession {
                HStack {
                    activePassChip(session, extraCount: activeSessions.count - 1)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 7)
            }
            Spacer()
        }
    }

    /// Live-countdown chip for the running pass (the soonest-expiring one
    /// when several run) — tap to reopen it.
    private func activePassChip(_ session: Session, extraCount: Int = 0) -> some View {
        Button { passTarget = session } label: {
            HStack(spacing: 7) {
                TicketGlyph(width: 16, tint: .white, perforation: Theme.success)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(countdownText(max(0, session.expiresAt.timeIntervalSince(context.date))))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                }
                Text("· \(zoneLabel(session.zoneCode, operator: session.parkingOperator))\(extraCount > 0 ? " · +\(extraCount) more" : "")")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background(Theme.success, in: Capsule())
            .shadow(color: Theme.success.opacity(0.35), radius: 7, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Active pass, tap to view")
    }

    /// Always-on incentive: the running "likely saved" total, one tap from the
    /// dashboard. Lives top-right so the number is seen on every open.
    private var savingsPill: some View {
        let avoided = SavingsStats.totals(in: modelContext).avoidedAED
        return Button {
            showLedger = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.coral)
                Text("~\(formatAED(avoided))")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelPrimary)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
            .frame(minHeight: 44) // touch target ≥ 44pt even though the pill is slim
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Savings: about \(formatAED(avoided)) dirhams in fines likely avoided")
        .accessibilityHint("Shows your savings dashboard")
    }

    // MARK: - Bottom sheet

    /// §13: nag gently until the Bluetooth automation has fired at least once.
    private var setupBanner: some View {
        Button { showShortcutGuide = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish setup")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.labelPrimary)
                    Text("Auto-open when you leave the car isn't active yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.labelSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.labelTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
            .padding(.horizontal, 10)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeSession == nil, let backup = voidedBackup, backup.expiresAt > .now {
                restoreBanner(backup)
            }
            if let session = activeSession, !payingSecondTicket {
                activeSessionContent(session)
            } else if let spot = designatedSpot, let designation = spot.designation {
                designatedContent(spot: spot, designation: designation)
            } else if dismissed {
                dismissedContent
            } else if verdict.paymentRequired || payingSecondTicket {
                payContent
            } else {
                freeContent
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.sheetRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sheetRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
        .padding(.horizontal, 10)
        // Float clear of the iOS 26 hovering tab bar.
        .padding(.bottom, 60)
        .animation(Theme.sheetSpring, value: verdict)
        .animation(Theme.sheetSpring, value: activeSession != nil)
    }

    /// The undo for a mistaken void — visible until the pass would have
    /// expired anyway.
    private func restoreBanner(_ backup: VoidedPass) -> some View {
        Button {
            restoreVoidedPass(backup)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voided by mistake? Restore your pass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.labelPrimary)
                    Text("\(zoneLabel(backup.zoneCode, operator: ParkingOperator(rawValue: backup.operatorRaw ?? "") ?? .parkin)) · runs until \(backup.expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.labelSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.labelTertiary)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(PressScaleStyle())
        .padding(.bottom, 14)
    }

    // State A/B — payment required
    private var payContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if payingSecondTicket, let running = activeSession {
                Button {
                    payingSecondTicket = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back to my \(zoneLabel(running.zoneCode, operator: running.parkingOperator)) ticket")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.coral)
                }
                .padding(.bottom, 12)
            }
            HStack(spacing: 10) {
                TagPill(text: payTagText,
                        background: Theme.paidTagBackground, foreground: Theme.paidTagText, dot: Theme.coral)
                // Mis-tapped a letter or memory filled the wrong code?
                // Reopen the zone picker without losing the rest of the flow.
                if !zoneCode.isEmpty {
                    Button {
                        zoneCode = ""
                        manualZoneEntry = false
                    } label: {
                        Text("Change")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                }
                Spacer(minLength: 0)
            }

            Text("Pay before you go")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 12)
                .padding(.bottom, 5)

            if let hourlyRate = displayRate {
                (Text("\(verdict.reason) · about ").foregroundStyle(Theme.labelSecondary)
                 + Text("AED \(hourlyRate)").fontWeight(.semibold).foregroundStyle(Theme.labelPrimary)
                 + Text(" an hour here.").foregroundStyle(Theme.labelSecondary))
                    .font(.system(size: 14.5, weight: .medium))
            } else {
                // Parkonic tariffs vary by community and aren't published —
                // their confirmation SMS states the fee; we don't guess.
                (Text("\(verdict.reason) · ").foregroundStyle(Theme.labelSecondary)
                 + Text("Parkonic zone").fontWeight(.semibold).foregroundStyle(Theme.labelPrimary)
                 + Text(" — the reply SMS confirms the fee.").foregroundStyle(Theme.labelSecondary))
                    .font(.system(size: 14.5, weight: .medium))
            }

            // Driven by the editing flag, NOT by zoneCode content — the field
            // writes zoneCode, so an emptiness check would tear the field out
            // of the hierarchy on the first typed character (field-reported).
            // Tier/zone-less operators keep their compact entry always visible.
            if parkingOperator.zoneStyle == .tier || parkingOperator.zoneStyle == ZoneStyle.none
                || zoneCode.isEmpty || manualZoneEntry {
                zoneEntry
            }

            DurationControl(hours: $hours, maxHours: effectiveMaxHours)
                .padding(.top, 18)

            Button(action: startPay) {
                HStack(spacing: 8) {
                    Text(displayRate.map { "Pay \(hours) \(hours == 1 ? "hour" : "hours") · AED \(hours * $0)" }
                         ?? "Pay \(hours) \(hours == 1 ? "hour" : "hours") by SMS")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Theme.coral, in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.white)
                .shadow(color: Theme.coral.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!canPay)
            .opacity(canPay ? 1 : 0.5)
            .padding(.top, 15)

            Text(plate.isEmpty
                 ? "Add your plate in Settings first"
                 : payFootnote)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.labelTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            // No zone code needed — Parkin's own app detects the zone itself.
            // We stay the reminder layer; they take the payment leg.
            // (Parkonic zones aren't in Parkin's app — hidden there.)
            if parkingOperator == .parkin {
                Button {
                    extending = false
                    openParkinApp()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Pay in the Parkin app instead")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.coral.opacity(0.6), lineWidth: 1.2))
                    .foregroundStyle(Theme.coral)
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 10)
            }

            // §15: false trigger (drop-off, passenger) — one tap kills every nag.
            HStack(spacing: 0) {
                Button {
                    dismissed = true
                    ActivityLog.log(.notParkingDismissed, in: modelContext)
                    syncProtection()
                } label: {
                    Text("I'm not parking here")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
                // Teach the app about this place: your own spot (Home/Office —
                // paid zone or not, you don't pay here) or a genuinely
                // unzoned street (field-proven in Jebel Ali).
                Menu {
                    Button { markDesignated(.home) } label: {
                        Label("This is Home — never remind", systemImage: "house.fill")
                    }
                    Button { markDesignated(.office) } label: {
                        Label("This is Office — never remind", systemImage: "building.2.fill")
                    }
                    Button { markSpotFree() } label: {
                        Label("No Parkin zone here — it's free", systemImage: "checkmark.circle")
                    }
                } label: {
                    Text("Don't remind me here")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
        }
    }

    // Designated place (Home/Office) — the app stays silent here.
    private func designatedContent(spot: Spot, designation: SpotDesignation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TagPill(text: "\(designation.label) · no reminders",
                    background: Color(hex: 0xEFEDE7),
                    foreground: Theme.labelSecondary, dot: Theme.labelTertiary)

            Text("You're at \(designation.label.lowercased()).")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 12)

            Text("We stay quiet here — no nags, no morning reminders.")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
                .padding(.top, 4)

            HStack(spacing: 0) {
                Button {
                    payAnyway = true
                    recomputeVerdict()
                    syncProtection()
                } label: {
                    Text("I need to pay here today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .frame(maxWidth: .infinity)
                }
                Button {
                    spot.designation = nil
                    recomputeVerdict()
                    syncProtection()
                } label: {
                    Text("Not \(designation.label.lowercased()) anymore")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
        }
    }

    // False-trigger acknowledged
    private var dismissedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagPill(text: "Not parking", background: Color(hex: 0xEFEDE7),
                    foreground: Theme.labelSecondary, dot: Theme.labelTertiary)

            Text("Okay — no reminders.")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 12)

            Text("Nothing scheduled for this stop.")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
                .padding(.top, 4)

            Button {
                dismissed = false
                syncProtection()
            } label: {
                Text("Actually, I am parking")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
    }

    private var payTagText: String {
        switch parkingOperator {
        case .parkin:
            return zoneCode.isEmpty ? "Paid zone" : "Paid zone · Zone \(zoneCode.uppercased())"
        case .parkonic:
            return zoneCode.isEmpty
                ? "Parkonic zone"
                : "Parkonic · Zone \(ParkonicRules.normalizeZone(zoneCode))"
        case .mawaqif:
            return "Mawaqif · \(zoneCode.uppercased() == "P" ? "Premium" : "Standard")"
        case .sharjah, .ajman, .fujairah:
            return "\(parkingOperator.regionLabel) parking"
        }
    }

    /// Curated tariff letters ∪ letters from zones the user has paid before.
    private var zoneLetterChips: [String] {
        var letters = ParkinRules.zoneLetters
        for zone in recentZones {
            let suffix = String(zone.drop(while: \.isNumber))
            if suffix.count == 1, suffix.first!.isLetter, !letters.contains(suffix) {
                letters.append(suffix)
            }
        }
        return letters.sorted()
    }

    private var payFootnote: String {
        switch parkingOperator {
        case .parkin: return "One tap — you press send in Messages"
        case .parkonic: return "One tap — sends to 6670. \(ParkonicRules.simNote)"
        case .ajman: return "One SMS buys 1 hour in Ajman — extend by replying Y"
        default: return "One tap — sends to \(parkingOperator.smsNumber)"
        }
    }

    /// Flip between operators by hand — for signs the community map got wrong.
    private func switchOperator(to newOperator: ParkingOperator) {
        Diag.log("operator_switched", ["to": newOperator.rawValue])
        parkingOperator = newOperator
        operatorOverridden = true
        zoneCode = ""
        manualZoneEntry = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // State B zone entry: GPS names the district → user taps the sign's letter.
    // Manual field only when we couldn't place them (or they say we got it wrong).
    @ViewBuilder
    private var zoneEntry: some View {
        if parkingOperator.zoneStyle == .tier {
            mawaqifTierEntry
        } else if parkingOperator.zoneStyle == ZoneStyle.none {
            zonelessEntry
        } else if parkingOperator == .parkonic {
            parkonicZoneEntry
        } else if let community = suggestedCommunity, !manualZoneEntry {
            VStack(alignment: .leading, spacing: 10) {
                (Text("Zone \(String(community.number))").fontWeight(.bold)
                 + Text(" · \(community.displayName) — tap the letter on the sign"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.labelSecondary)

                Text("A guess from your location — the sign or meter wins if it differs.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.labelTertiary)

                // Curated letters (ParkinRules) plus any letter this user has
                // actually paid — a chip the field proves is never missing
                // again (J was, despite the user's own 393J ticket).
                HStack(spacing: 7) {
                    ForEach(zoneLetterChips, id: \.self) { letter in
                        Button {
                            zoneCode = "\(community.number)\(letter)"
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(letter)
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.labelPrimary)
                                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                        }
                    }
                }

                HStack(spacing: 18) {
                    Button {
                        manualZoneEntry = true
                        zoneFieldFocused = true
                    } label: {
                        Text("Different zone? Type the code")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                    scanSignButton
                }
                parkinToParkonicSwitch
            }
            .padding(.top, 14)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                manualZoneField
                parkinToParkonicSwitch
            }
        }
    }

    /// Escape hatch on the Parkin side: P-numbered signs mean Parkonic.
    private var parkinToParkonicSwitch: some View {
        Button {
            switchOperator(to: .parkonic)
        } label: {
            Text("Sign shows a P-number (like P105)? That's Parkonic")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.coral)
        }
    }

    /// Geofences are coarse near borders — let the user pick the operator.
    private var operatorMenu: some View {
        Menu {
            ForEach(ParkingOperator.allCases, id: \.self) { candidate in
                Button {
                    switchOperator(to: candidate)
                    if candidate.zoneStyle == .tier { zoneCode = "S" }
                } label: {
                    if candidate == parkingOperator {
                        Label("\(candidate.label) · \(candidate.regionLabel)", systemImage: "checkmark")
                    } else {
                        Text("\(candidate.label) · \(candidate.regionLabel)")
                    }
                }
            }
        } label: {
            Text("Wrong operator? Change")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.coral)
        }
    }

    /// Mawaqif (Abu Dhabi): no zones — just the kerb tier off the sign colour.
    private var mawaqifTierEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kerb tier — check the sign: turquoise-black is Standard, turquoise-white is Premium")
                .font(.system(size: 13))
                .foregroundStyle(Theme.labelTertiary)
            Picker("Kerb tier", selection: $zoneCode) {
                Text("Standard · AED 2/h").tag("S")
                Text("Premium · AED 3/h").tag("P")
            }
            .pickerStyle(.segmented)
            operatorMenu
        }
        .padding(.top, 14)
    }

    /// Sharjah / Ajman / Fujairah: one SMS covers the whole emirate.
    private var zonelessEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(parkingOperator.regionLabel) has no zone codes — one SMS covers the emirate.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.labelTertiary)
            operatorMenu
        }
        .padding(.top, 14)
    }

    /// Parkonic State B: no letter chips — the whole code (P105) is on the
    /// pole sign. Spot memory and recents fill it on repeat visits.
    private var parkonicZoneEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let community = suggestedCommunity {
                (Text(community.displayName).fontWeight(.bold)
                 + Text(" is a Parkonic community — the P-zone is on the pole sign"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.labelSecondary)
            }

            TextField("P-zone from the pole sign, e.g. P105", text: $zoneCode)
                .font(.system(size: 16, weight: .semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($zoneFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    zoneCode = ParkonicRules.normalizeZone(zoneCode)
                    zoneFieldFocused = false
                    manualZoneEntry = false
                }
                // Same lesson as the RTA field (field-reported twice now):
                // the field writes zoneCode, and visibility checks emptiness —
                // so editing mode must pin the field open or the first typed
                // character tears it out of the hierarchy.
                .onChange(of: zoneFieldFocused) {
                    if zoneFieldFocused { manualZoneEntry = true }
                }
                .onChange(of: zoneCode) {
                    zoneCode = zoneCode.replacingOccurrences(of: " ", with: "").uppercased()
                }
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)

            if !recentZones.filter({ $0.hasPrefix("P") }).isEmpty {
                HStack(spacing: 7) {
                    ForEach(recentZones.filter { $0.hasPrefix("P") }.prefix(3), id: \.self) { zone in
                        Button { zoneCode = zone } label: {
                            Text(zone)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(.white, in: Capsule())
                                .foregroundStyle(Theme.labelPrimary)
                                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                        }
                    }
                }
            }

            Button {
                switchOperator(to: .parkin)
            } label: {
                Text("Not Parkonic? Switch to an RTA zone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(.top, 14)
    }

    /// Task 5: read the full code (number + letter) off the sign, on-device.
    @ViewBuilder
    private var scanSignButton: some View {
        if ZoneScan.isSupported {
            Button {
                showScanner = true
            } label: {
                Label("Scan the sign", systemImage: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private var manualZoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Zone code — blue/orange sign, e.g. 444A", text: $zoneCode)
                .font(.system(size: 16, weight: .semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($zoneFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    zoneFieldFocused = false
                    manualZoneEntry = false
                }
                // Entering edit mode (however focus arrived — a direct tap or
                // the "type the code" button) pins the field open while
                // characters land; see the visibility comment in payContent.
                .onChange(of: zoneFieldFocused) {
                    if zoneFieldFocused { manualZoneEntry = true }
                }
                .onChange(of: zoneCode) {
                    zoneCode = zoneCode.replacingOccurrences(of: " ", with: "").uppercased()
                }
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                // No auto-focus: the keyboard appears only on the user's own
                // tap (field-reported — it hijacked every app open, and pinned
                // manual mode so the chips could never appear).

            scanSignButton

            if !recentZones.isEmpty {
                HStack(spacing: 7) {
                    ForEach(recentZones.prefix(3), id: \.self) { zone in
                        Button { zoneCode = zone } label: {
                            Text(zone)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(.white, in: Capsule())
                                .foregroundStyle(Theme.labelPrimary)
                                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    // State C — free
    private var freeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagPill(text: "Free right now", background: Theme.freeTagBackground,
                    foreground: Theme.success, dot: Theme.success)

            Text("You're free to walk away.")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 12)

            (Text(verdict.reason).foregroundStyle(Theme.labelSecondary)
             + Text(" · no payment needed here").foregroundStyle(Theme.labelTertiary))
                .font(.system(size: 14.5, weight: .medium))
                .padding(.top, 4)

            // Accidental "No paid parking here"? One tap takes it back.
            if zoneKind == .free {
                Button {
                    revertFreeSpot()
                } label: {
                    Text("Wrong — it's actually paid here")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 14)
            }

            if let next = verdict.nextChange {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                    Text("We'll remind you at \(reminderTimeText(before: next))")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.labelPrimary)
                    Spacer(minLength: 0)
                    Text(next.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.labelTertiary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                .padding(.top, 16)
            }
        }
    }

    // State D (M1 mini) — active session
    private func activeSessionContent(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TagPill(text: "Paid · \(zoneLabel(session.zoneCode, operator: session.parkingOperator))",
                    background: Theme.freeTagBackground,
                    foreground: Theme.success, dot: Theme.success)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, session.expiresAt.timeIntervalSince(context.date))
                Text(countdownText(remaining))
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .kerning(-1)
                    .foregroundStyle(Theme.labelPrimary)
                    .padding(.top, 12)
            }

            Text("remaining · expires \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
                .padding(.top, 2)

            HStack(spacing: 10) {
                Button { passTarget = session } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("View pass")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.coral, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.coral.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(PressScaleStyle())

                Button {
                    NotificationManager.shared.extendTargetSessionID = session.id
                    extending = true
                    if session.paidViaParkinApp { openParkinApp() } else { startComposerFlow() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("+1 hr")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 15)
                    .padding(.horizontal, 18)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.coral, lineWidth: 1.5))
                    .foregroundStyle(Theme.coral)
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.top, 16)

            // Every OTHER running ticket, right here on Home (field request:
            // two tickets were live but only My Spots showed the second).
            let others = activeSessions.filter { $0.id != session.id }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Also running")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                    ForEach(others) { other in
                        Button { passTarget = other } label: {
                            HStack(spacing: 9) {
                                TicketGlyph(width: 16, tint: Theme.success, perforation: .white)
                                Text(zoneLabel(other.zoneCode, operator: other.parkingOperator))
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Theme.labelPrimary)
                                Spacer(minLength: 8)
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(countdownText(max(0, other.expiresAt.timeIntervalSince(context.date))))
                                        .font(.system(size: 14.5, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.labelPrimary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.labelTertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 13)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.top, 14)
            }

            // Field reality (TestFlight): Parkin can reject the SMS ("Invalid
            // Zone") after the user already confirmed. Give them a way out —
            // but behind a confirmation: this deletes a live pass, and a
            // stray tap once cost the user a pass with 1:54 remaining.
            Button {
                showVoidConfirm = true
            } label: {
                Text("Payment didn't go through? Fix zone & resend")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 12)
            .confirmationDialog("Void this pass?", isPresented: $showVoidConfirm,
                                titleVisibility: .visible) {
                Button("Void it — the payment failed", role: .destructive) {
                    voidSession(session)
                }
                Button("Keep my pass", role: .cancel) {}
            } message: {
                Text("Only if \(session.parkingOperator.label) rejected or never confirmed the payment. Your remaining time is removed — you can restore it from the next screen if this was a mistake.")
            }

            // Moved zones with time still on this ticket? Both can run —
            // this one stays live while you pay for the new place.
            Button {
                payingSecondTicket = true
                manualZoneEntry = false
            } label: {
                Text("Parking somewhere else? Pay a new ticket")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 10)
        }
    }

    /// Home/Office: remember this place and stay silent here — the zone may be
    /// genuinely paid (for visitors), the user just has their own arrangement.
    private func markDesignated(_ designation: SpotDesignation) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let matched = matchedSpot {
            matched.designation = designation
        } else if let coordinate = location.coordinate {
            let spot = Spot(name: designation.label, coordinate: coordinate,
                            zoneCode: zoneCode.uppercased(), kind: zoneKind,
                            designation: designation)
            modelContext.insert(spot)
            matchedSpot = spot
        }
        payAnyway = false
        syncProtection()
    }

    /// Undo for an accidental "No paid parking here": forget the free marking
    /// and re-run the normal decision for this location.
    private func revertFreeSpot() {
        if let matched = matchedSpot, matched.zoneKind == .free {
            modelContext.delete(matched)
            matchedSpot = nil
        }
        zoneKind = .standard
        zoneCode = ""
        recomputeVerdict()
        syncProtection()
    }

    /// "No paid parking here": remember this location as free — the verdict
    /// flips now and on every future visit within the spot radius.
    private func markSpotFree() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let matched = matchedSpot {
            matched.zoneKindRaw = ZoneKind.free.rawValue
            matched.zoneCode = ""
        } else if let coordinate = location.coordinate {
            modelContext.insert(Spot(name: location.areaName ?? "Free parking",
                                     coordinate: coordinate, zoneCode: "", kind: .free))
        }
        zoneKind = .free
        zoneCode = ""
        recomputeVerdict()
        syncProtection()
    }

    /// Rolls back a session whose payment turned out to have failed: the pass,
    /// meter, widget, reminders, save credit — and the zone memory the phantom
    /// payment created (spot + recents), so the bad code can't auto-fill again.
    private func voidSession(_ session: Session) {
        // Keep a snapshot until the pass would have expired — mistaken voids
        // get an in-place undo.
        voidedBackup = VoidedPass(plate: session.plate, zoneCode: session.zoneCode,
                                  kindRaw: session.zoneKindRaw,
                                  operatorRaw: session.operatorRaw,
                                  startedAt: session.startedAt,
                                  durationHours: session.durationHours,
                                  extendedCount: session.extendedCount,
                                  expiresAt: session.expiresAt)
        Diag.log("session_voided", ["op": session.parkingOperator.rawValue])
        InterventionLog.voidSession(sessionID: session.id, in: modelContext)
        modelContext.delete(session)
        NotificationManager.shared.cancelSessionReminders(sessionID: session.id)
        LiveActivityManager.end()
        WidgetSessionStore.clear()
        if let spot = spots.first(where: { $0.zoneCode == session.zoneCode }) {
            if spot.timesParked <= 1 {
                modelContext.delete(spot)
            } else {
                spot.timesParked -= 1
            }
        }
        recentZonesCSV = recentZones.filter { $0 != session.zoneCode }.joined(separator: ",")
        matchedSpot = nil
        zoneCode = ""
        passTarget = nil
        manualZoneEntry = true
        recomputeVerdict()
        syncProtection()
    }

    /// Undo a mistaken void: rebuild the session exactly as it was (extends
    /// included) and put the pass, reminders, and widget back. The ledger
    /// credit revoked by the void stays revoked — under-counting a save is
    /// the honest direction.
    private func restoreVoidedPass(_ backup: VoidedPass) {
        Diag.log("session_restored")
        let session = Session(plate: backup.plate, zoneCode: backup.zoneCode,
                              kind: ZoneKind(rawValue: backup.kindRaw) ?? .standard,
                              durationHours: backup.durationHours,
                              startedAt: backup.startedAt)
        session.extendedCount = backup.extendedCount
        session.expiresAt = backup.expiresAt
        session.paymentAttempted = true
        session.userConfirmedPaid = true
        session.operatorRaw = backup.operatorRaw
        modelContext.insert(session)
        voidedBackup = nil
        NotificationManager.shared.scheduleExpiryReminders(
            sessionID: session.id,
            zoneText: zoneLabel(session.zoneCode, operator: session.parkingOperator),
            expiresAt: session.expiresAt)
        LiveActivityManager.start(zoneCode: session.zoneCode, plate: session.plate,
                                  startedAt: session.startedAt, expiresAt: session.expiresAt)
        WidgetSessionStore.save(zoneCode: session.zoneCode, plate: session.plate,
                                startedAt: session.startedAt, expiresAt: session.expiresAt)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        recomputeVerdict()
        syncProtection()
        passTarget = session
    }

    // MARK: - Pipeline (§8)

    private func runPipeline() {
        dismissed = false
        manualZoneEntry = false
        payAnyway = false
        operatorOverridden = false
        payingSecondTicket = false
        hours = max(1, defaultHours)
        location.requestOneShot()
        recomputeVerdict()
        // Interventions whose window closed without action are not saves.
        InterventionLog.closePastDeadline(in: modelContext)
        syncProtection()
        // Keep the widget in step with the truth: refresh it while a session
        // runs, take the meter off the lock screen and widget once it's over.
        if let session = soonestActiveSession {
            // Two tickets? The lock screen tracks the one expiring first —
            // that's the urgent one.
            WidgetSessionStore.save(zoneCode: session.zoneCode, plate: session.plate,
                                    startedAt: session.startedAt, expiresAt: session.expiresAt)
        } else {
            LiveActivityManager.end()
            WidgetSessionStore.clear()
        }
        // Automation/demo hook: `simctl launch ... -demoSession` seeds a paid session.
        if CommandLine.arguments.contains("-demoSession"), activeSession == nil {
            let demo = Session(plate: plate.isEmpty ? "A44821" : plate,
                               zoneCode: "444A", kind: .standard, durationHours: 1)
            demo.paymentAttempted = true
            demo.userConfirmedPaid = true
            modelContext.insert(demo)
            LiveActivityManager.start(zoneCode: demo.zoneCode, plate: demo.plate,
                                      startedAt: demo.startedAt, expiresAt: demo.expiresAt)
            WidgetSessionStore.save(zoneCode: demo.zoneCode, plate: demo.plate,
                                    startedAt: demo.startedAt, expiresAt: demo.expiresAt)
            passTarget = demo
        }
    }

    /// Reconciles layers 3+4 with the current state — schedules what should fire,
    /// cancels what shouldn't. Called on every state transition (§9: "cancel
    /// scheduled notifications correctly when state changes").
    /// Every schedule/cancel is mirrored into the intervention log (Task 1):
    /// scheduling upserts a pending event, cancelling discards it if it never
    /// fired. Fired events stay pending for resolvePayment/resolveExtend.
    private func syncProtection() {
        let manager = NotificationManager.shared
        let now = Date.now
        if activeSession != nil || dismissed || designatedSpot != nil {
            manager.cancelUnpaidNag()
            manager.cancelMorningReminder()
            InterventionLog.discardUnfired(kinds: [.unpaidNag, .morningFreeToPaid],
                                           in: modelContext, now: now)
        } else if verdict.paymentRequired {
            manager.cancelMorningReminder()
            InterventionLog.discardUnfired(kinds: [.morningFreeToPaid], in: modelContext, now: now)
            manager.scheduleUnpaidNag(zone: zoneCode.uppercased())
            if manager.remindNag {
                let fireAt = now.addingTimeInterval(ParkinRules.nagDelay)
                InterventionLog.upsertScheduled(
                    kind: .unpaidNag, zone: zoneCode.uppercased(), fireAt: fireAt,
                    deadline: fireAt.addingTimeInterval(ParkinRules.nagResolveWindow),
                    sessionID: nil, in: modelContext, now: now)
            }
        } else {
            manager.cancelUnpaidNag()
            InterventionLog.discardUnfired(kinds: [.unpaidNag], in: modelContext, now: now)
            if let next = verdict.nextChange {
                let zoneLabel = zoneCode.isEmpty ? "This area" : "Zone \(zoneCode.uppercased())"
                manager.scheduleMorningReminder(zone: zoneLabel, paidStart: next)
                if manager.remindMorning {
                    InterventionLog.upsertScheduled(
                        kind: .morningFreeToPaid, zone: zoneCode.uppercased(),
                        fireAt: next.addingTimeInterval(-Double(morningLeadMinutes) * 60),
                        deadline: next, sessionID: nil, in: modelContext, now: now)
                }
            }
        }
    }

    private func handleLocationFix() {
        guard let coordinate = location.coordinate else { return }
        withAnimation(Theme.crossFade) {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
        // Spot match: auto-fill the zone (40 m; free/home spots match at 150 m).
        if let match = spots
            .filter({ $0.distance(from: coordinate) <= $0.matchRadius })
            .min(by: { $0.distance(from: coordinate) < $1.distance(from: coordinate) }) {
            matchedSpot = match
            zoneCode = match.zoneCode
            zoneKind = match.zoneKind
            parkingOperator = match.parkingOperator
        }
        // District lookup: pre-fills the zone *number*; the sign supplies the letter.
        suggestedCommunity = ZoneLocator.community(at: coordinate)
        Diag.log("detect", [
            "lat": Diag.coarse(coordinate.latitude),
            "lon": Diag.coarse(coordinate.longitude),
            "community": suggestedCommunity?.number as Any,
            "spot": matchedSpot != nil,
        ])
        // Operator resolution — spot memory and a manual flip both outrank it.
        // Inside Dubai (community polygons hit): Parkin, or Parkonic for
        // JVC/DSO/Gardens. Outside Dubai: coarse emirate geofences.
        if matchedSpot == nil, !operatorOverridden {
            if let community = suggestedCommunity {
                parkingOperator = ParkonicRules.isParkonicCommunity(community.number)
                    ? .parkonic : .parkin
            } else if let regional = EmirateLocator.parkingOperator(at: coordinate) {
                parkingOperator = regional
                // Mawaqif's "zone" is the kerb tier — default Standard.
                if parkingOperator.zoneStyle == .tier, zoneCode.isEmpty { zoneCode = "S" }
                if parkingOperator.zoneStyle == ZoneStyle.none { zoneCode = "" }
            } else {
                parkingOperator = .parkin
            }
        }
        // Quiet value moments, debounced to one per visit.
        if let spot = matchedSpot {
            if let designation = spot.designation {
                ActivityLog.log(.quietArrival, label: designation.label, in: modelContext)
            } else if spot.zoneKind == .free {
                ActivityLog.log(.freeArrival, label: spot.name, in: modelContext)
            }
        }
        recomputeVerdict()
        syncProtection()
    }

    private func recomputeVerdict() {
        // The user's own correction outranks the debug switch — otherwise
        // "No paid parking here" looks broken while force-paid is on.
        if zoneKind == .free {
            verdict = ParkinRules.verdict(kind: .free)
            return
        }
        if debugForcePaid {
            verdict = Verdict(paymentRequired: true,
                              reason: "Forced paid — debug switch is on in Settings",
                              nextChange: nil)
            return
        }
        verdict = RegionRules.verdict(for: parkingOperator, kind: zoneKind)
        hours = min(hours, effectiveMaxHours)
    }

    /// UI cap (3) ∩ what the paid window allows ∩ what one SMS can buy
    /// (Ajman sells exactly 1 hour per message).
    private var effectiveMaxHours: Int {
        min(3,
            RegionRules.maxPayableHours(for: parkingOperator, kind: zoneKind),
            parkingOperator.maxHoursPerSMS)
    }

    // MARK: - Pay flow

    private func startPay() {
        extending = false
        Diag.log("pay_started", ["op": parkingOperator.rawValue, "zone": zoneCode.uppercased(),
                                 "hours": hours, "canSMS": MessageComposer.canSendText])
        ActivityLog.log(.smsPayStarted, label: zoneCode.uppercased(), in: modelContext)
        startComposerFlow()
    }

    private func startComposerFlow() {
        if MessageComposer.canSendText {
            showComposer = true
        } else {
            // Simulator / no-SMS devices: flow continues so it stays testable.
            showConfirm = true
        }
    }

    /// Hand the payment leg to Parkin's own app — their zone database does the
    /// detecting. We ask the honest question when the user comes back.
    private func openParkinApp() {
        ActivityLog.log(.parkinOpened, label: zoneCode.uppercased(), in: modelContext)
        paidViaParkin = true
        awaitingParkinReturn = true
        // App-routing chain (field-driven, builds 45–46): the scheme is
        // confirmed from Parkin's own smart-banner meta (parkin://home) and
        // attempted DIRECTLY — canOpenURL misreported on a device that had
        // the app installed. Then both universal-link hosts app-only; last
        // resort is their homepage in Safari, whose smart banner opens the
        // installed app in one tap. Never the App Store.
        var chain: [(URL, Bool)] = []
        if let scheme = URL(string: ParkinRules.parkinAppScheme) { chain.append((scheme, false)) }
        if let apex = URL(string: ParkinRules.parkinUniversalLinkApex) { chain.append((apex, true)) }
        if let www = URL(string: ParkinRules.parkinUniversalLink) { chain.append((www, true)) }
        func tryOpen(_ candidates: [(URL, Bool)]) {
            guard let (url, appOnly) = candidates.first else {
                Diag.log("parkin_handoff", ["path": "safari"])
                if let site = URL(string: ParkinRules.parkinWebsite) {
                    UIApplication.shared.open(site)
                }
                return
            }
            UIApplication.shared.open(url, options: appOnly ? [.universalLinksOnly: true] : [:]) { opened in
                if opened {
                    Diag.log("parkin_handoff", ["path": url.absoluteString])
                } else {
                    tryOpen(Array(candidates.dropFirst()))
                }
            }
        }
        tryOpen(chain)
    }

    private func confirmPaid() {
        Diag.log("confirm_paid", ["op": parkingOperator.rawValue, "extending": extending,
                                  "viaParkinApp": paidViaParkin])
        showConfirm = false
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        let now = Date.now
        if extending, let session = extendTarget {
            // A fired expiry warning followed by this extend = a likely save.
            InterventionLog.resolveExtend(sessionID: session.id, at: now,
                                          fineAED: session.parkingOperator.assumedFineAED,
                                          in: modelContext)
            session.extend()
            extending = false
            NotificationManager.shared.extendTargetSessionID = nil
            NotificationManager.shared.scheduleExpiryReminders(
                sessionID: session.id,
                zoneText: zoneLabel(session.zoneCode, operator: session.parkingOperator),
                expiresAt: session.expiresAt)
            logExpiryIntervention(for: session, now: now)
            LiveActivityManager.update(startedAt: session.startedAt, expiresAt: session.expiresAt)
            WidgetSessionStore.update(startedAt: session.startedAt, expiresAt: session.expiresAt)
            return
        }

        // Store the zone the way the operator writes it (P105, not 105; S/P
        // tiers uppercase).
        if parkingOperator == .parkonic {
            zoneCode = ParkonicRules.normalizeZone(zoneCode)
        } else if parkingOperator.zoneStyle == .tier {
            zoneCode = zoneCode.uppercased()
        }
        let session = Session(plate: plate, zoneCode: zoneCode, kind: zoneKind, durationHours: hours)
        session.paymentAttempted = true
        session.userConfirmedPaid = true
        session.paidViaParkinApp = paidViaParkin
        session.parkingOperator = parkingOperator
        paidViaParkin = false
        modelContext.insert(session)
        // A fired nag/morning reminder followed by this payment = a likely save.
        InterventionLog.resolvePayment(zone: session.zoneCode.uppercased(),
                                       sessionID: session.id, at: now,
                                       fineAED: parkingOperator.assumedFineAED,
                                       in: modelContext)
        rememberSpotAndZone()
        // Paid: the nag and morning reminder are off the table; expiry watch begins.
        NotificationManager.shared.cancelUnpaidNag()
        NotificationManager.shared.cancelMorningReminder()
        InterventionLog.discardUnfired(kinds: [.unpaidNag, .morningFreeToPaid],
                                       in: modelContext, now: now)
        payingSecondTicket = false
        NotificationManager.shared.scheduleExpiryReminders(
            sessionID: session.id,
            zoneText: zoneLabel(session.zoneCode, operator: session.parkingOperator),
            expiresAt: session.expiresAt)
        logExpiryIntervention(for: session, now: now)
        LiveActivityManager.start(zoneCode: session.zoneCode, plate: session.plate,
                                  startedAt: session.startedAt, expiresAt: session.expiresAt)
        WidgetSessionStore.save(zoneCode: session.zoneCode, plate: session.plate,
                                startedAt: session.startedAt, expiresAt: session.expiresAt)
        passTarget = session
    }

    /// Mirrors scheduleExpiryReminders into the log. The −10 min warning and the
    /// at-expiry alert are one intervention; its deadline is the lapse itself.
    private func logExpiryIntervention(for session: Session, now: Date) {
        guard NotificationManager.shared.remindExpiry else { return }
        let fireAt = session.expiresAt.addingTimeInterval(-ParkinRules.expiryWarningLead)
        InterventionLog.upsertScheduled(
            kind: .expiryWarning, zone: session.zoneCode.uppercased(),
            fireAt: max(fireAt, now), deadline: session.expiresAt,
            sessionID: session.id, in: modelContext, now: now)
    }

    private func rememberSpotAndZone() {
        // Parkin-app payments may not know the zone code — nothing to remember.
        guard !zoneCode.isEmpty else { return }
        var zones = recentZones.filter { $0 != zoneCode.uppercased() }
        zones.insert(zoneCode.uppercased(), at: 0)
        recentZonesCSV = zones.prefix(5).joined(separator: ",")

        guard let coordinate = location.coordinate else { return }
        if let matched = matchedSpot {
            matched.timesParked += 1
            matched.lastParkedAt = .now
            // The place remembers who runs it — a Parkonic payment here means
            // next arrival goes straight to the P-zone flow.
            matched.parkingOperator = parkingOperator
            matched.zoneCode = zoneCode.uppercased()
        } else {
            let name = location.areaName ?? "Spot \(spots.count + 1)"
            let spot = Spot(name: name, coordinate: coordinate,
                            zoneCode: zoneCode.uppercased(), kind: zoneKind)
            spot.parkingOperator = parkingOperator
            modelContext.insert(spot)
        }
    }

    // MARK: - Helpers

    private func countdownText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private func reminderTimeText(before paidStart: Date) -> String {
        paidStart.addingTimeInterval(-Double(morningLeadMinutes) * 60)
            .formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Components

private struct TagPill: View {
    let text: String
    let background: Color
    let foreground: Color
    let dot: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(background, in: Capsule())
    }
}

struct DurationControl: View {
    @Binding var hours: Int
    var maxHours: Int = 3

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...max(1, maxHours), id: \.self) { h in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { hours = h }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 1) {
                        Text("\(h)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(hours == h ? Theme.labelPrimary : Theme.labelSecondary)
                        Text(h == 1 ? "hour" : "hours")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.labelTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        hours == h ? AnyShapeStyle(.white) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Theme.segmentedThumbRadius)
                    )
                    .shadow(color: hours == h ? .black.opacity(0.1) : .clear, radius: 2, y: 1)
                }
            }
        }
        .padding(5)
        .background(Theme.segmentedTrack, in: RoundedRectangle(cornerRadius: Theme.segmentedTrackRadius))
    }
}

struct CarPin: View {
    let reduceMotion: Bool
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Theme.coral.opacity(0.18))
                    .frame(width: 74, height: 74)
                    .scaleEffect(pulsing ? 1.6 : 0.45)
                    .opacity(pulsing ? 0 : 0.9)
                    .onAppear {
                        withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                            pulsing = true
                        }
                    }
            }
            Circle()
                .fill(Theme.coral)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.32), radius: 4.5, y: 1.5)

            Text("Your car")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.labelPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 5, y: 1.5)
                .offset(y: -34)
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension CLLocationCoordinate2D {
    /// Default camera before the first fix — Al Barsha, Dubai.
    static let alBarsha = CLLocationCoordinate2D(latitude: 25.1124, longitude: 55.1965)
}
