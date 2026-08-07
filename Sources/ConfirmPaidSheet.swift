import SwiftUI

/// The honesty sheet (§9): iOS can't read the operator's confirmation SMS, so we
/// ask once and only ever mark a session paid when the user says so.
struct ConfirmPaidSheet: View {
    let smsBody: String
    var viaParkinApp = false
    var parkingOperator: ParkingOperator = .parkin
    let onConfirm: () -> Void
    let onNotYet: () -> Void

    private var operatorName: String { parkingOperator.label }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Payment preview
            VStack(alignment: .leading, spacing: 5) {
                Text(viaParkinApp ? "In the Parkin app" : "To \(parkingOperator.smsNumber)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.labelSecondary)
                Text(viaParkinApp ? "Parking payment" : smsBody)
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.smsPreviewBackground, in: RoundedRectangle(cornerRadius: 15))
            .padding(.bottom, 16)

            Text(viaParkinApp ? "Did you pay in Parkin?" : "Did \(operatorName) confirm it?")
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(Theme.labelPrimary)

            Text(viaParkinApp
                 ? "If Parkin shows your session active, you're covered — confirm and the countdown and expiry reminders run here too."
                 : "Watch for the reply from \(parkingOperator.smsNumber) — it lists a ticket and expiry. If it says the zone is invalid, fix it and resend. We only mark it paid when you say \(operatorName) confirmed.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.labelSecondary)
                .lineSpacing(3)
                .padding(.top, 6)

            Button(action: onConfirm) {
                Text("\(operatorName) confirmed ✓")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.success, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .padding(.top, 18)

            Button(action: onNotYet) {
                Text("No reply yet / it failed")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Theme.labelSecondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .presentationDetents([.height(350)])
        .presentationCornerRadius(Theme.sheetRadius)
        .presentationDragIndicator(.visible)
    }
}
