import SwiftUI
import SwiftData
import CryptoKit

struct SettingsView: View {
    @AppStorage("plate") private var plate = ""
    @AppStorage("plateEmirate") private var plateEmirate = Emirate.dubai.rawValue
    @AppStorage("plateLetters") private var plateLetters = ""
    @AppStorage("plateNumber") private var plateNumber = ""
    @AppStorage("defaultHours") private var defaultHours = 1
    @AppStorage("debugForcePaid") private var debugForcePaid = false
    @AppStorage("remindMorning") private var remindMorning = true
    @AppStorage("remindNag") private var remindNag = true
    @AppStorage("remindExpiry") private var remindExpiry = true
    @AppStorage("morningLeadMinutes") private var morningLeadMinutes = 15
    @AppStorage("mapSatellite") private var mapSatellite = false
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [Session]
    @State private var showGuide = false

    // Presenter Mode (hidden): 7 taps on the version row, then the passcode.
    // Only the presenter's demo needs demo data — everyone else lives on the
    // real ledger.
    @AppStorage("presenterMode") private var presenterMode = false
    @State private var versionTaps = 0
    @State private var showPresenterGate = false
    @State private var presenterPasscode = ""
    /// SHA-256 of the presenter passcode — the code itself is never in the app.
    private let presenterHash = "b8bf4d22948b82a2f26cc490e00155406c1a11d93bc10c7edfe6e297298d92a2"

    private var isTestBuild: Bool { DemoData.isTestBuild }

    private var plateProfile: PlateProfile {
        PlateProfile(emirate: Emirate(rawValue: plateEmirate) ?? .dubai,
                     letters: plateLetters, number: plateNumber)
    }

    /// The legacy single-string key stays in sync (Parkin format) — sessions,
    /// widget, and older code paths keep reading it.
    private func syncLegacyPlate() {
        plate = plateProfile.parkinPlate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Emirate", selection: $plateEmirate) {
                        ForEach(Emirate.allCases) { emirate in
                            Text("\(emirate.label) · \(emirate.rawValue)").tag(emirate.rawValue)
                        }
                    }
                    TextField("Letters — e.g. BB", text: $plateLetters)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, weight: .semibold))
                        .onChange(of: plateLetters) {
                            plateLetters = plateLetters.uppercased().filter(\.isLetter)
                            syncLegacyPlate()
                        }
                    TextField("Number — e.g. 60925", text: $plateNumber)
                        .keyboardType(.numberPad)
                        .font(.system(size: 17, weight: .semibold))
                        .onChange(of: plateNumber) {
                            plateNumber = plateNumber.filter(\.isNumber)
                            syncLegacyPlate()
                        }
                } header: {
                    Text("Your plate")
                } footer: {
                    if plateNumber.isEmpty {
                        Text("Each operator writes your plate its own way — we format it for you.")
                    } else {
                        Text("Texts as \(plateProfile.parkinPlate) to Parkin (7275) · \(plateProfile.parkonicPlate) to Parkonic (6670).")
                    }
                }

                Section("Default duration") {
                    Picker("Hours", selection: $defaultHours) {
                        ForEach(1...3, id: \.self) { Text("\($0) hour\($0 == 1 ? "" : "s")") }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Before paid hours start", isOn: $remindMorning)
                    if remindMorning {
                        Picker("Lead time", selection: $morningLeadMinutes) {
                            ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before") }
                        }
                    }
                    Toggle("If you forget to pay (5-min nag)", isOn: $remindNag)
                    Toggle("Before your session expires", isOn: $remindExpiry)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Park during free hours and we warn you before charging starts (e.g. 7:45 AM Monday). Expiry alerts include a one-tap +1 hour action.")
                }

                Section("Stats") {
                    NavigationLink {
                        SavingsLedgerView()
                    } label: {
                        Label("Savings — fines likely avoided", systemImage: "shield.checkered")
                    }
                    // Threshold-gated so a two-session recap doesn't feel silly;
                    // always visible in test builds (the "force generate" path).
                    if sessions.filter(\.userConfirmedPaid).count >= ParkinRules.recapMinimumSessions
                        || isTestBuild {
                        NavigationLink {
                            RecapScreen()
                        } label: {
                            Label("Your year in parking", systemImage: "sparkles")
                        }
                    }
                }

                Section {
                    Toggle("Satellite imagery", isOn: $mapSatellite)
                } header: {
                    Text("Map")
                } footer: {
                    Text("Satellite view shows actual parking bays and lot layouts.")
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics log", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("A local record of what the app did — share it with the developer if something misbehaves. Nothing is sent anywhere on its own.")
                }

                Section {
                    HStack {
                        Text("Yalla Park")
                        Spacer()
                        Text("0.9.5 (63)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                    // Invisible owner's switch: 7 taps. Demo profile OFF →
                    // passcode, then the testing data is simply there. ON →
                    // silently back to real. Nothing on screen ever says so.
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 7 {
                            versionTaps = 0
                            if presenterMode {
                                setPresenterMode(false)
                            } else {
                                showPresenterGate = true
                            }
                        }
                    }
                } header: {
                    Text("About")
                }

                Section("Automation") {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Set up auto-open when leaving the car", systemImage: "bolt.car.fill")
                    }
                }

                Section {
                    LabeledContent("RTA Parkin SMS", value: ParkinRules.smsNumber)
                    LabeledContent("Parkonic SMS", value: ParkonicRules.smsNumber)
                    LabeledContent("Carrier fee", value: "AED \(String(format: "%.2f", ParkinRules.smsCarrierFeeAED)) per SMS")
                } header: {
                    Text("How it works")
                } footer: {
                    Text("Your location stays on this device. No account, no server. We pre-fill your own SMS to the right operator — Parkin for RTA zones, Parkonic for P-zones (JVC, DSO, The Gardens) — and never mark a session paid unless you confirm it. \(ParkonicRules.simNote)")
                }

                if isTestBuild {
                    Section {
                        Toggle("Force \"payment required\"", isOn: $debugForcePaid)
                        Button("Start 1-hour demo session") {
                            let demo = Session(plate: plate.isEmpty ? "A44821" : plate,
                                               zoneCode: "444A", kind: .standard, durationHours: 1)
                            demo.paymentAttempted = true
                            demo.userConfirmedPaid = true
                            modelContext.insert(demo)
                            LiveActivityManager.start(zoneCode: demo.zoneCode, plate: demo.plate,
                                                      startedAt: demo.startedAt,
                                                      expiresAt: demo.expiresAt)
                            NotificationManager.shared.scheduleExpiryReminders(
                                sessionID: demo.id,
                                zoneText: zoneLabel(demo.zoneCode, operator: .parkin),
                                expiresAt: demo.expiresAt)
                        }
                        Button("Clear all sessions", role: .destructive) {
                            for session in sessions { modelContext.delete(session) }
                            NotificationManager.shared.cancelAll()
                            LiveActivityManager.end()
                        }
                        Button("Fire test notifications (4 s + 8 s)") {
                            NotificationManager.shared.fireTestNotifications()
                        }
                        Button("Seed 6 months of demo stats") {
                            DemoData.seedSixMonths(in: modelContext)
                        }
                        Button("Clear stats & history", role: .destructive) {
                            DemoData.clearStats(in: modelContext)
                        }
                        // Savings-model accuracy at a glance (Task 2): if fines
                        // creep up relative to saves, the windows need tuning.
                        let totals = SavingsStats.totals(in: modelContext)
                        LabeledContent("Savings model",
                                       value: "\(totals.remindersFired) fired · \(totals.likelySaves) likely saves · \(totals.finesReported) fines reported")
                    } header: {
                        Text("Testing")
                    } footer: {
                        Text("Visible in TestFlight builds only. \"Force payment required\" previews the amber pay flow even during free hours; the demo session puts the live countdown on your lock screen and Dynamic Island.")
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(Theme.coral)
            .sheet(isPresented: $showGuide) {
                OnboardingView(startAtShortcut: true) { showGuide = false }
            }
            .alert("Passcode", isPresented: $showPresenterGate) {
                SecureField("Passcode", text: $presenterPasscode)
                Button("Unlock") { unlockPresenter() }
                Button("Cancel", role: .cancel) { presenterPasscode = "" }
            }
        }
    }

    private func unlockPresenter() {
        let digest = SHA256.hash(data: Data(presenterPasscode.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        presenterPasscode = ""
        guard hex == presenterHash else { return }
        setPresenterMode(true)
    }

    /// ON: seed the demo year if the ledger has none. OFF: wipe it clean.
    private func setPresenterMode(_ on: Bool) {
        presenterMode = on
        UINotificationFeedbackGenerator().notificationOccurred(on ? .success : .warning)
        Diag.log("demo_profile", ["on": on])
        if on {
            let decisive = (try? modelContext.fetchCount(FetchDescriptor<InterventionEvent>(
                predicate: #Predicate { $0.decisive }))) ?? 0
            if decisive == 0 { DemoData.seedSixMonths(in: modelContext) }
        } else {
            DemoData.clearStats(in: modelContext)
            NotificationManager.shared.cancelAll()
            LiveActivityManager.end()
        }
    }
}
