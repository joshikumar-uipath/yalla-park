import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("plate") private var plate = ""
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

    /// True in Xcode debug runs and TestFlight installs; false for App Store copies —
    /// so the testing section disappears automatically at public release.
    private var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. A44821", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, weight: .semibold))
                } header: {
                    Text("Plate number")
                } footer: {
                    Text("Dubai plates only in this version — exactly as you'd text it to 7275, e.g. A44821.")
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

                Section("Automation") {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Set up auto-open when leaving the car", systemImage: "bolt.car.fill")
                    }
                }

                Section {
                    LabeledContent("Pay by SMS", value: ParkinRules.smsNumber)
                    LabeledContent("Carrier fee", value: "AED \(String(format: "%.2f", ParkinRules.smsCarrierFeeAED)) per SMS")
                } header: {
                    Text("How it works")
                } footer: {
                    Text("Your location stays on this device. No account, no server. We pre-fill your own SMS to Parkin — we never touch money and never mark a session paid unless you confirm it.")
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
                                zone: demo.zoneCode, expiresAt: demo.expiresAt)
                        }
                        Button("Clear all sessions", role: .destructive) {
                            for session in sessions { modelContext.delete(session) }
                            NotificationManager.shared.cancelAll()
                            LiveActivityManager.end()
                        }
                        Button("Fire test notifications (4 s + 8 s)") {
                            NotificationManager.shared.fireTestNotifications()
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
        }
    }
}
