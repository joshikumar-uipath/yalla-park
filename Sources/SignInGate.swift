import SwiftUI
import AuthenticationServices

/// The front door (two-tier decision 2026-08-24: signed + Pro, no anonymous
/// tier). One sign-in, once — then the app is the app. Serverless as ever:
/// the identity stays between the user and Apple, data on device + their
/// own iCloud.
///
/// Motion (all skipped under Reduce Motion): a staged entrance — the mark
/// springs in, the wordmark rises, the pass slides up — then a slow ambient
/// float on the mark, a drifting perforation on the tear line, and one
/// green car from the year lot driving across behind the pass.
struct SignInGateView: View {
    private let theme = SavingsTheme.light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var signInError: String?

    // Entrance stages: 0 nothing → 1 mark → 2 words → 3 pass.
    @State private var stage = 0
    @State private var floating = false
    @State private var carX: CGFloat = -90
    @State private var carVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.page.ignoresSafeArea()

                // The drive-by: a lot car crossing behind the pass, once.
                if carVisible {
                    // The open lane BELOW the pass — a drive-by nobody can
                    // miss (behind the card it was fully occluded).
                    CarView(theme: theme, tone: 0)
                        .rotationEffect(.degrees(90))
                        .offset(x: carX, y: geo.size.height * 0.405)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    TicketGlyph(width: 52, tint: theme.ticketA, perforation: theme.page)
                        .scaleEffect(stage >= 1 ? 1 : 0.3)
                        .opacity(stage >= 1 ? 1 : 0)
                        .rotationEffect(.degrees(stage >= 1 ? 0 : -14))
                        .offset(y: floating ? -3.5 : 3.5)

                    Group {
                        Text("Yalla Park")
                            .font(.system(size: 34, weight: .heavy))
                            .kerning(-0.8)
                            .foregroundStyle(theme.pageText)
                            .padding(.top, 14)
                        Text("Never pay a parking fine again.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.secCap)
                            .padding(.top, 4)
                    }
                    .opacity(stage >= 2 ? 1 : 0)
                    .offset(y: stage >= 2 ? 0 : 14)

                    Spacer(minLength: 24)

                    passCard
                        .opacity(stage >= 3 ? 1 : 0)
                        .offset(y: stage >= 3 ? 0 : 90)

                    Spacer(minLength: 40)
                }
            }
        }
        .alert("Couldn't sign in", isPresented: Binding(
            get: { signInError != nil },
            set: { if !$0 { signInError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInError ?? "")
        }
        .onAppear(perform: runEntrance)
    }

    private var passCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TicketGlyph(width: 15, tint: theme.ticketA, perforation: .white)
                Text("YOUR PASS")
                    .font(.system(size: 11.5, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(theme.secCap)
            }
            Text("One sign-in, and the app remembers every zone you park in, every ticket you buy, and every fine it likely saves you — across all six UAE operators.")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(theme.stubText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)

            TearLine(color: theme.stubDash, drifting: !reduceMotion)
                .overlay(alignment: .leading) {
                    Circle().fill(theme.page).frame(width: 22, height: 22).offset(x: -29)
                }
                .overlay(alignment: .trailing) {
                    Circle().fill(theme.page).frame(width: 22, height: 22).offset(x: 29)
                }
                .padding(.vertical, 17)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                signInError = Account.handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("We run no servers — your identity stays between you and Apple, your data on this phone and your own iCloud.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.secCap)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 11)
        }
        .padding(18)
        .background(theme.stub, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 18)
    }

    private func runEntrance() {
        guard stage == 0 else { return }
        if reduceMotion {
            stage = 3
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { stage = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.22)) { stage = 2 }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.42)) { stage = 3 }
        // Ambient float begins once the entrance settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        // One car crosses the lot behind the pass, then leaves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            carVisible = true
            withAnimation(.easeInOut(duration: 2.6)) {
                carX = UIScreen.main.bounds.width + 90
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { carVisible = false }
        }
    }
}

/// A dashed tear line whose dashes drift slowly — the ticket wanting to be
/// torn. Static under Reduce Motion.
private struct TearLine: View {
    let color: Color
    let drifting: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        Line()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [5, 5], dashPhase: phase))
            .frame(height: 2)
            .onAppear {
                guard drifting else { return }
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    phase = -20
                }
            }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}
