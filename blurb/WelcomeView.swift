import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.95), .purple, .pink.opacity(0.82), .blue.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(.white.opacity(0.32), lineWidth: 1)
                    }

                Text("A question a day,\nfor your people.")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("Blurb keeps your closest groups connected through the little things worth sharing.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 36)

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        auth.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text("Your groups stay private. Your answers stay yours.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
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
