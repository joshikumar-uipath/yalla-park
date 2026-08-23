import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Apple, serverless. The stable Apple user ID lives in
/// UserDefaults (views observe it via @AppStorage("appleUserID")); the
/// coming CloudKit sync keys off the same iCloud identity, so no account
/// backend ever exists. Signing in unlocks the "remembered" tier: the full
/// savings story now, unlimited spots + history next.
enum Account {
    static var userID: String? {
        let id = UserDefaults.standard.string(forKey: "appleUserID")
        return (id?.isEmpty ?? true) ? nil : id
    }
    static var isSignedIn: Bool { userID != nil }

    /// Owner allowlist: SHA-256 hex of Apple user IDs whose sign-in turns
    /// the demo profile on automatically (the owner's own devices — his
    /// "my login shows the testing data" request). Populated from the
    /// owner's first sign-in, captured via Diagnostics.
    static let demoAllowlist: Set<String> = []

    static func completeSignIn(credential: ASAuthorizationAppleIDCredential) {
        let defaults = UserDefaults.standard
        defaults.set(credential.user, forKey: "appleUserID")
        if let name = credential.fullName {
            let display = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
            if !display.isEmpty { defaults.set(display, forKey: "appleUserName") }
        }
        if let email = credential.email { defaults.set(email, forKey: "appleUserEmail") }
        let hash = SHA256.hash(data: Data(credential.user.utf8))
            .map { String(format: "%02x", $0) }.joined()
        // The uid/hash land in Diagnostics so the owner's ID can be added to
        // demoAllowlist — after that his devices get demo data on sign-in.
        Diag.log("siwa_signed_in", ["uid": credential.user, "hash": hash])
        if demoAllowlist.contains(hash) {
            defaults.set(true, forKey: "presenterMode")
        }
    }

    static func signOut() {
        let defaults = UserDefaults.standard
        for key in ["appleUserID", "appleUserName", "appleUserEmail"] {
            defaults.removeObject(forKey: key)
        }
        Diag.log("siwa_signed_out")
    }

    /// Apple can revoke the credential (user removes the app in Settings →
    /// Apple ID) — honor it on every launch.
    static func verifyCredentialState() {
        guard let id = userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { state, _ in
            if state == .revoked || state == .notFound {
                DispatchQueue.main.async {
                    Diag.log("siwa_revoked")
                    signOut()
                }
            }
        }
    }
}
