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
    @AppStorage("recentZones") private var recentZonesCSV = ""
    @AppStorage("debugForcePaid") private var debugForcePaid = false

    @State private var location = LocationService()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .alBarsha, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
    )

    @State private var zoneCode = ""
    @State private var zoneKind: ZoneKind = .standard
    @State private var matchedSpot: Spot?
    /// GPS-derived district → zone number suggestion (ZoneLocator).
    @State private var suggestedCommunity: Community?
    @State private var manualZoneEntry = false
    @State private var verdict: Verdict = ParkinRules.verdict(kind: .standard)
    @State private var hours = 1

    @State private var showComposer = false
    @State private var showConfirm = false
    @State private var showPass = false
    @State private var extending = false
    @State private var dismissed = false
    @State private var showShortcutGuide = false
    @AppStorage("morningLeadMinutes") private var morningLeadMinutes = 15
    @AppStorage("defaultHours") private var defaultHours = 1
    @AppStorage("automationVerified") private var automationVerified = false
    @AppStorage("setupMarkedDone") private var setupMarkedDone = false
    /// Home savings card: dismiss hides it until the save count grows again.
    @AppStorage("savingsCardDismissedCount") private var savingsCardDismissedCount = 0
    @State private var showLedger = false
    @FocusState private var zoneFieldFocused: Bool

    private var activeSession: Session? { sessions.first(where: \.isActive) }
    private var recentZones: [String] {
        recentZonesCSV.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
    private var rate: Int { ParkinRules.estimatedRateAED(zone: zoneCode, kind: zoneKind) }
    private var smsBody: String {
        ParkinRules.smsBody(plate: plate, zone: zoneCode, hours: extending ? 1 : hours)
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
        .onAppear { runPipeline() }
        .onChange(of: router.parkedTrigger) { runPipeline() }
        .onChange(of: router.extendTrigger) {
            guard activeSession != nil else { return }
            extending = true
            startComposerFlow()
        }
        .onChange(of: location.fixID) { handleLocationFix() }
        .sheet(isPresented: $showComposer, onDismiss: { showConfirm = true }) {
            MessageComposer(recipients: [ParkinRules.smsNumber], body: smsBody) {
                showComposer = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmPaidSheet(
                smsBody: smsBody,
                onConfirm: confirmPaid,
                onNotYet: { showConfirm = false }
            )
        }
        // A sheet, not fullScreenCover, so the pass swipes away naturally;
        // "Back to map" stays as the discoverable path.
        .sheet(isPresented: $showPass) {
            if let session = activeSession {
                PassScreen(session: session, onClose: { showPass = false })
                    .presentationDragIndicator(.visible)
            }
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
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
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
                    Text("· just now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.labelSecondary)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
        }
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
            if let session = activeSession {
                activeSessionContent(session)
            } else if dismissed {
                dismissedContent
            } else if verdict.paymentRequired {
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

    // State A/B — payment required
    private var payContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagPill(text: zoneCode.isEmpty ? "Paid zone" : "Paid zone · Zone \(zoneCode.uppercased())",
                    background: Theme.paidTagBackground, foreground: Theme.paidTagText, dot: Theme.coral)

            Text("Pay before you go")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 12)
                .padding(.bottom, 5)

            (Text("\(verdict.reason) · about ").foregroundStyle(Theme.labelSecondary)
             + Text("AED \(rate)").fontWeight(.semibold).foregroundStyle(Theme.labelPrimary)
             + Text(" an hour here.").foregroundStyle(Theme.labelSecondary))
                .font(.system(size: 14.5, weight: .medium))

            if zoneCode.isEmpty {
                zoneEntry
            }

            DurationControl(hours: $hours, maxHours: min(3, ParkinRules.maxPayableHours(kind: zoneKind)))
                .padding(.top, 18)

            Button(action: startPay) {
                HStack(spacing: 8) {
                    Text("Pay \(hours) \(hours == 1 ? "hour" : "hours") · AED \(hours * rate)")
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
            .disabled(plate.isEmpty || zoneCode.isEmpty)
            .opacity(plate.isEmpty || zoneCode.isEmpty ? 0.5 : 1)
            .padding(.top, 15)

            Text(plate.isEmpty
                 ? "Add your plate in Settings first"
                 : "One tap — you press send in Messages")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.labelTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            // §15: false trigger (drop-off, passenger) — one tap kills every nag.
            Button {
                dismissed = true
                syncProtection()
            } label: {
                Text("I'm not parking here")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 10)
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

    // State B zone entry: GPS names the district → user taps the sign's letter.
    // Manual field only when we couldn't place them (or they say we got it wrong).
    @ViewBuilder
    private var zoneEntry: some View {
        if let community = suggestedCommunity, !manualZoneEntry {
            VStack(alignment: .leading, spacing: 10) {
                (Text("Zone \(String(community.number))").fontWeight(.bold)
                 + Text(" · \(community.displayName) — tap the letter on the sign"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.labelSecondary)

                HStack(spacing: 7) {
                    ForEach(["A", "B", "C", "D", "W"], id: \.self) { letter in
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

                Button {
                    manualZoneEntry = true
                    zoneFieldFocused = true
                } label: {
                    Text("Different zone? Type the code")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
            }
            .padding(.top, 14)
        } else {
            manualZoneField
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
                .onSubmit { zoneFieldFocused = false }
                .onChange(of: zoneCode) {
                    zoneCode = zoneCode.replacingOccurrences(of: " ", with: "").uppercased()
                }
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                // The whole point of the trigger is "phone out, type the sign" —
                // have the keyboard ready without an extra tap.
                .onAppear { zoneFieldFocused = true }

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
            TagPill(text: "Paid · Zone \(session.zoneCode)", background: Theme.freeTagBackground,
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
                Button { showPass = true } label: {
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
                    extending = true
                    startComposerFlow()
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
        }
    }

    // MARK: - Pipeline (§8)

    private func runPipeline() {
        dismissed = false
        manualZoneEntry = false
        hours = max(1, defaultHours)
        location.requestOneShot()
        recomputeVerdict()
        // Interventions whose window closed without action are not saves.
        InterventionLog.closePastDeadline(in: modelContext)
        syncProtection()
        // Keep the widget in step with the truth: refresh it while a session
        // runs, take the meter off the lock screen and widget once it's over.
        if let session = activeSession {
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
            showPass = true
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
        if activeSession != nil || dismissed {
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
        // Spot match (~40 m): strong matches auto-fill the zone.
        if let match = spots
            .filter({ $0.distance(from: coordinate) <= Spot.matchRadiusMeters })
            .min(by: { $0.distance(from: coordinate) < $1.distance(from: coordinate) }) {
            matchedSpot = match
            zoneCode = match.zoneCode
            zoneKind = match.zoneKind
        }
        // District lookup: pre-fills the zone *number*; the sign supplies the letter.
        suggestedCommunity = ZoneLocator.community(at: coordinate)
        recomputeVerdict()
        syncProtection()
    }

    private func recomputeVerdict() {
        if debugForcePaid {
            verdict = Verdict(paymentRequired: true,
                              reason: "Charging until 10:00 PM", nextChange: nil)
            return
        }
        verdict = ParkinRules.verdict(kind: zoneKind)
        hours = min(hours, ParkinRules.maxPayableHours(kind: zoneKind))
    }

    // MARK: - Pay flow

    private func startPay() {
        extending = false
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

    private func confirmPaid() {
        showConfirm = false
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        let now = Date.now
        if extending, let session = activeSession {
            // A fired expiry warning followed by this extend = a likely save.
            InterventionLog.resolveExtend(sessionID: session.id, at: now, in: modelContext)
            session.extend()
            extending = false
            NotificationManager.shared.scheduleExpiryReminders(
                zone: session.zoneCode, expiresAt: session.expiresAt)
            logExpiryIntervention(for: session, now: now)
            LiveActivityManager.update(startedAt: session.startedAt, expiresAt: session.expiresAt)
            WidgetSessionStore.update(startedAt: session.startedAt, expiresAt: session.expiresAt)
            return
        }

        let session = Session(plate: plate, zoneCode: zoneCode, kind: zoneKind, durationHours: hours)
        session.paymentAttempted = true
        session.userConfirmedPaid = true
        modelContext.insert(session)
        // A fired nag/morning reminder followed by this payment = a likely save.
        InterventionLog.resolvePayment(zone: session.zoneCode.uppercased(),
                                       sessionID: session.id, at: now, in: modelContext)
        rememberSpotAndZone()
        // Paid: the nag and morning reminder are off the table; expiry watch begins.
        NotificationManager.shared.cancelUnpaidNag()
        NotificationManager.shared.cancelMorningReminder()
        InterventionLog.discardUnfired(kinds: [.unpaidNag, .morningFreeToPaid],
                                       in: modelContext, now: now)
        NotificationManager.shared.scheduleExpiryReminders(
            zone: session.zoneCode, expiresAt: session.expiresAt)
        logExpiryIntervention(for: session, now: now)
        LiveActivityManager.start(zoneCode: session.zoneCode, plate: session.plate,
                                  startedAt: session.startedAt, expiresAt: session.expiresAt)
        WidgetSessionStore.save(zoneCode: session.zoneCode, plate: session.plate,
                                startedAt: session.startedAt, expiresAt: session.expiresAt)
        showPass = true
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
        var zones = recentZones.filter { $0 != zoneCode.uppercased() }
        zones.insert(zoneCode.uppercased(), at: 0)
        recentZonesCSV = zones.prefix(5).joined(separator: ",")

        guard let coordinate = location.coordinate else { return }
        if let matched = matchedSpot {
            matched.timesParked += 1
            matched.lastParkedAt = .now
        } else {
            let name = location.areaName ?? "Spot \(spots.count + 1)"
            modelContext.insert(Spot(name: name, coordinate: coordinate,
                                     zoneCode: zoneCode.uppercased(), kind: zoneKind))
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
