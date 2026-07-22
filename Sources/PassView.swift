import SwiftUI

/// The active-session "parking pass" — visual source of truth is the `#pass` view
/// in dxb-park-map-pass.html. This card's design IS the future Live Activity (M4).
struct PassView: View {
    let session: Session
    let onExtend: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.passCanvasTop, Theme.passCanvasBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active session")
                            .font(.system(size: 26, weight: .bold))
                            .kerning(-0.7)
                            .foregroundStyle(Theme.labelPrimary)
                        HStack(spacing: 6) {
                            Circle().fill(Theme.success).frame(width: 8, height: 8)
                            Text("Paid · you're covered")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.success)
                        }
                    }
                    .padding(.horizontal, 6)

                    PassCard(session: session)
                        .padding(.top, 18)

                    Button {
                        // Real .pkpass issuance needs an Apple pass-type ID — later milestone.
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wallet.pass.fill")
                            Text("Add to Apple Wallet")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.black, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                    .disabled(true)
                    .opacity(0.35)
                    .padding(.top, 16)

                    Button(action: onExtend) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("Extend +1 hour")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.coral, lineWidth: 1.5))
                        .foregroundStyle(Theme.coral)
                    }
                    .buttonStyle(PressScaleStyle())
                    .padding(.top, 10)

                    Button(action: onClose) {
                        Text("Back to map")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.labelSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
        }
    }
}

/// Owns the extend flow so it can present the composer + honesty sheet
/// above the full-screen pass.
struct PassScreen: View {
    @Bindable var session: Session
    let onClose: () -> Void

    @State private var showComposer = false
    @State private var showConfirm = false

    private var extendBody: String {
        ParkinRules.smsBody(plate: session.plate, zone: session.zoneCode, hours: 1)
    }

    var body: some View {
        PassView(session: session, onExtend: startExtend, onClose: onClose)
            .sheet(isPresented: $showComposer, onDismiss: { showConfirm = true }) {
                MessageComposer(recipients: [ParkinRules.smsNumber], body: extendBody) {
                    showComposer = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showConfirm) {
                ConfirmPaidSheet(
                    smsBody: extendBody,
                    onConfirm: {
                        showConfirm = false
                        session.extend()
                        NotificationManager.shared.scheduleExpiryReminders(
                            zone: session.zoneCode, expiresAt: session.expiresAt)
                        LiveActivityManager.update(startedAt: session.startedAt,
                                                   expiresAt: session.expiresAt)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    },
                    onNotYet: { showConfirm = false }
                )
            }
    }

    private func startExtend() {
        if MessageComposer.canSendText {
            showComposer = true
        } else {
            showConfirm = true
        }
    }
}

struct PassCard: View {
    let session: Session

    private var totalSeconds: TimeInterval {
        session.expiresAt.timeIntervalSince(session.startedAt)
    }
    private var paidAmount: Double {
        let rate = ParkinRules.estimatedRateAED(zone: session.zoneCode, kind: session.zoneKind)
        return Double(session.durationHours * rate) + ParkinRules.smsCarrierFeeAED
    }

    var body: some View {
        VStack(spacing: 0) {
            // Gradient header
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text("P")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                    Text("DXB Park")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(zoneLabel(session.zoneCode))
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.92)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, session.expiresAt.timeIntervalSince(context.date))
                    let fraction = totalSeconds > 0 ? remaining / totalSeconds : 0

                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.countdown(remaining))
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                            .kerning(-1)
                            .padding(.top, 16)

                        Text("remaining · expires \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 13.5, weight: .medium))
                            .opacity(0.9)
                            .padding(.top, 2)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.28))
                                Capsule()
                                    .fill(fraction < 0.15 ? Theme.lowTimeWarning : .white)
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 16)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .background(
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xFB4E2A), location: 0),
                            .init(color: Color(hex: 0xFF6E3C), location: 0.55),
                            .init(color: Color(hex: 0xFF5168), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [Color(hex: 0xFF9A54), .clear],
                        center: UnitPoint(x: 0.85, y: 0),
                        startRadius: 0, endRadius: 240
                    )
                }
            )

            // Fields
            HStack(alignment: .top, spacing: 10) {
                passField("Plate", session.plate)
                passField("Started", session.startedAt.formatted(date: .omitted, time: .shortened))
                Spacer()
                passField("Paid", "AED \(String(format: "%.2f", paidAmount))", trailing: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Perforation
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color(hex: 0xE6E4DE))
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Barcode
            BarcodeStrip(seed: session.id.uuidString)
                .frame(height: 64)
                .padding(.horizontal, 22)
                .padding(.top, 15)
                .padding(.bottom, 18)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Color(.sRGB, red: 200/255, green: 60/255, blue: 20/255, opacity: 0.26),
                radius: 20, y: 8)
    }

    private func passField(_ key: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(key.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.labelSecondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.labelPrimary)
        }
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Decorative barcode, deterministic per session.
struct BarcodeStrip: View {
    let seed: String

    var body: some View {
        let widths: [CGFloat] = [2, 2, 4, 2, 6, 2]
        let scalars = Array(seed.unicodeScalars)
        HStack(spacing: 2) {
            ForEach(0..<54, id: \.self) { i in
                let scalar = scalars[i % scalars.count]
                Rectangle()
                    .fill(Theme.labelPrimary)
                    .frame(width: widths[Int(scalar.value) % widths.count])
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
