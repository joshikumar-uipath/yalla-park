import SwiftUI
import CoreLocation
import UserNotifications

/// First-run flow (§7): promise → plate → the Shortcut walkthrough (§13) → permissions.
/// Also re-presentable from Settings ("Set up the automation") jumping straight to step 3.
struct OnboardingView: View {
    var startAtShortcut = false
    let onDone: () -> Void

    @AppStorage("plate") private var plate = ""
    @State private var step = 0
    @State private var copied = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.passCanvasTop, Theme.passCanvasBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Theme.coral : Color(hex: 0xDDDAD2))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $step) {
                    promise.tag(0)
                    plateEntry.tag(1)
                    shortcutSetup.tag(2)
                    permissions.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.crossFade, value: step)
            }
        }
        .onAppear { if startAtShortcut { step = 2 } }
    }

    // MARK: Step 1 — the promise

    private var promise: some View {
        OnboardingPage(
            icon: "car.fill",
            title: "Never get a parking fine because you forgot.",
            subtitle: "Your car tells us the second you leave it. We check the zone, the day, and the clock — and get payment one tap away before you've crossed the street."
        ) {
            PrimaryButton("Let's set it up") { step = 1 }
        }
    }

    // MARK: Step 2 — plate

    private var plateEntry: some View {
        OnboardingPage(
            icon: "rectangle.and.text.magnifyingglass",
            title: "Your plate",
            subtitle: "Exactly as you'd text it to 7275 — Dubai plates only for now, e.g. A44821."
        ) {
            VStack(spacing: 12) {
                TextField("A44821", text: $plate)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    .onChange(of: plate) {
                        plate = plate.replacingOccurrences(of: " ", with: "").uppercased()
                    }

                PrimaryButton("Continue", disabled: !plateLooksValid) { step = 2 }
            }
        }
    }

    private var plateLooksValid: Bool {
        plate.range(of: #"^[A-Z]{1,3}\d{1,5}$"#, options: .regularExpression) != nil
    }

    // MARK: Step 3 — the magic (Shortcut automation)

    private var shortcutSetup: some View {
        OnboardingPage(
            icon: "bolt.car.fill",
            title: "Set up the magic",
            subtitle: "One iOS automation makes the app open itself the moment you switch off the car. Two minutes, once."
        ) {
            VStack(alignment: .leading, spacing: 11) {
                stepRow(1, "Open the **Shortcuts** app → **Automation** tab → **＋**")
                stepRow(2, "Choose **Bluetooth** → select your car's stereo → **When Disconnected**")
                stepRow(3, "Pick **Run Immediately** (turn off \"Ask Before Running\")")
                stepRow(4, "Add action **Open URLs** and paste:")

                HStack(spacing: 10) {
                    Text("dxbpark://parked")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.labelPrimary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = "dxbpark://parked"
                        copied = true
                    } label: {
                        Text(copied ? "Copied ✓" : "Copy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(copied ? Theme.success : Theme.coral)
                    }
                }
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)

                Text("Use **CarPlay → When Disconnecting** instead if your car has CarPlay.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.labelTertiary)

                Button {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Open Shortcuts app")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.coral, lineWidth: 1.5))
                    .foregroundStyle(Theme.coral)
                }
                .padding(.top, 4)

                PrimaryButton("Done — continue") { step = 3 }

                Button {
                    step = 3
                } label: {
                    Text("I'll do it later")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.coral, in: Circle())
            Text(.init(text))
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 4 — permissions (primed, never cold)

    private var permissions: some View {
        OnboardingPage(
            icon: "checkmark.shield.fill",
            title: "Two permissions, honestly explained",
            subtitle: "Location — one reading when you park, to recognize the zone; it never leaves your phone. Notifications — the reminders that actually stop the fines."
        ) {
            PrimaryButton("Enable and start") {
                let locationManager = CLLocationManager()
                locationManager.requestWhenInUseAuthorization()
                Task {
                    _ = await NotificationManager.shared.ensureAuthorized()
                    await MainActor.run { onDone() }
                }
            }
        }
    }
}

// MARK: - Shared page chrome

private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .padding(.top, 36)

                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.labelPrimary)
                    .padding(.top, 18)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Theme.labelSecondary)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                content
                    .padding(.top, 26)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
        }
    }
}

private struct PrimaryButton: View {
    let label: String
    var disabled = false
    let action: () -> Void

    init(_ label: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.coral, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(.white)
                .shadow(color: Theme.coral.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}
