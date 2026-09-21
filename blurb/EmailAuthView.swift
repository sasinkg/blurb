import SwiftUI

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager
    @State private var creatingAccount = false
    @State private var confirmation = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resetMessage: String?

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && (!creatingAccount || password == confirmation)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(creatingAccount ? "Join your people." : "Welcome back.")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                    Text(creatingAccount ? "Create your account, then make your profile your own." : "Enter your email and password to continue.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email address").font(.subheadline.weight(.medium))
                            TextField("you@example.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("emailAddress")
                                .authInput()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password").font(.subheadline.weight(.medium))
                            SecureField("Password", text: $password)
                                .textContentType(creatingAccount ? .newPassword : .password)
                                .accessibilityIdentifier("emailPassword")
                                .authInput()
                        }
                        if creatingAccount {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Confirm password").font(.subheadline.weight(.medium))
                                SecureField("Confirm password", text: $confirmation)
                                    .textContentType(.newPassword)
                                    .accessibilityIdentifier("emailPasswordConfirmation")
                                    .authInput()
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("emailAuthError")
                    }
                    if let resetMessage {
                        Text(resetMessage).font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        Button(action: submit) {
                            HStack {
                                if isSubmitting { ProgressView().tint(.white) }
                                Text(creatingAccount ? "Create account" : "Sign in")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white)
                            .background(Color.blue.opacity(canSubmit ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isSubmitting)
                        .accessibilityIdentifier("emailAuthSubmit")

                        Button(creatingAccount ? "Back to sign in" : "Sign up") {
                            creatingAccount.toggle()
                            confirmation = ""
                            password = ""
                            errorMessage = nil
                            resetMessage = nil
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.primary)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("emailAuthSwitchMode")

                        if !creatingAccount {
                            Button("Forgot password?", action: resetPassword)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.blue)
                                .padding(.vertical, 8)
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .disabled(isSubmitting)
            .navigationTitle(creatingAccount ? "Sign up" : "Sign in with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        resetMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                if creatingAccount {
                    try await auth.createAccount(email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
                password = ""
                confirmation = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetPassword() {
        guard !isSubmitting else { return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address above, then tap Forgot password."
            return
        }
        isSubmitting = true
        errorMessage = nil
        resetMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await auth.sendPasswordReset(email: email)
                resetMessage = "If this email has a password account, you'll receive a password reset link. Check your inbox and spam folder."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension View {
    func authInput() -> some View {
        self.padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)) }
    }
}
