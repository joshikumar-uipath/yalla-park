import SwiftUI
import AuthenticationServices

/// The front door (two-tier decision 2026-08-24: signed + Pro, no anonymous
/// tier). One sign-in, once — then the app is the app. Serverless as ever:
/// the identity stays between the user and Apple, data on device + their
/// own iCloud.
struct SignInGateView: View {
    private let theme = SavingsTheme.light
    @State private var signInError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            TicketGlyph(width: 52, tint: theme.ticketA, perforation: theme.page)
            Text("Yalla Park")
                .font(.system(size: 34, weight: .heavy))
                .kerning(-0.8)
                .foregroundStyle(theme.pageText)
                .padding(.top, 14)
            Text("Never pay a parking fine again.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.secCap)
                .padding(.top, 4)

            Spacer(minLength: 24)

            // The pass to claim — same anatomy as everything else here.
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

                DashedRule(color: theme.stubDash, thickness: 2)
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

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page.ignoresSafeArea())
        .alert("Couldn't sign in", isPresented: Binding(
            get: { signInError != nil },
            set: { if !$0 { signInError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInError ?? "")
        }
    }
}
