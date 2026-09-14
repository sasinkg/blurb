import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.055, green: 0.055, blue: 0.05)
                : Color(red: 0.965, green: 0.95, blue: 0.88))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("THE DAILY BLURB")
                    .font(.caption.weight(.black))
                    .tracking(2.4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(red: 1, green: 0.78, blue: 0.02))
                    .foregroundStyle(.black)

                Text("A question a day,\nfor your people.")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.top, 48)

                Text("Blurb keeps your closest groups connected through the little things worth sharing.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 36)

                ZStack {
                    Color.black
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.02))
                }
                .frame(maxWidth: .infinity, minHeight: 245)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 22)

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        auth.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text("Your groups stay private. Your answers stay yours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 34)
            }
        }
        .alert("Couldn’t sign in", isPresented: Binding(
            get: { auth.errorMessage != nil },
            set: { if !$0 { auth.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "Please try again.")
        }
    }
}
