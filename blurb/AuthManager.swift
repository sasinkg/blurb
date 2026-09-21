import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Security
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isLoading = true
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private var listener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    init() {
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard self?.isAuthenticating != true else { return }
            self?.user = user
            self?.isLoading = false
        }
    }

    deinit {
        if let listener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }

        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let tokenData = appleCredential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple did not return a valid sign-in token. Please try again."
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            Task {
                guard !isAuthenticating else { return }
                isAuthenticating = true
                defer { finishAuthentication() }
                do {
                    let result = try await Auth.auth().signIn(with: credential)
                    let name = PersonNameComponentsFormatter().string(from: appleCredential.fullName ?? PersonNameComponents())
                    await prepareProfile(for: result.user, displayName: name)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { finishAuthentication() }
        let result = try await Auth.auth().signIn(
            withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        await prepareProfile(for: result.user)
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func createAccount(email: String, password: String) async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { finishAuthentication() }
        let result = try await Auth.auth().createUser(
            withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        await prepareProfile(for: result.user)
    }

    private func finishAuthentication() {
        // Publish the session only after profile setup so the signed-in UI doesn't
        // start with a missing profile. Auth failures leave the welcome screen visible.
        user = Auth.auth().currentUser
        isLoading = false
        isAuthenticating = false
    }

    private func prepareProfile(for user: User, displayName: String = "") async {
        do {
            try await createProfileIfNeeded(for: user, displayName: displayName)
        } catch {
            // Authentication already succeeded. Don't misreport a created account
            // as a failed sign-in. Profile setup can be retried on the next login.
            errorMessage = "You're signed in, but your profile couldn't be saved. You can update it from Profile or sign in again to retry. \(error.localizedDescription)"
        }
    }

    func signOut() {
        guard let userID = user?.uid else { return }
        Task {
            await NotificationManager.shared.removeReplyToken(for: userID)
            do {
                try Auth.auth().signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSession() async -> Bool {
        guard let user else { return false }
        do {
            let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                user.getIDTokenForcingRefresh(true) { token, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let token {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "DailyBurb.Auth",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Firebase did not return an authentication token."]
                        ))
                    }
                }
            }
            let claims = Self.tokenClaims(from: token)
            let configuredProject = FirebaseApp.app()?.options.projectID ?? "missing"
            let audience = claims?["aud"] as? String ?? "missing"

            guard audience == configuredProject else {
                try? Auth.auth().signOut()
                errorMessage = "Firebase Authentication and Firestore are using different projects. Expected \(configuredProject), but the sign-in token belongs to \(audience)."
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func tokenClaims(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    func deleteCurrentAccount() async -> Bool {
        guard let user else { return false }
        do {
            try await user.delete()
            return true
        } catch {
            errorMessage = (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue
                ? "For security, sign out and sign in again before deleting your account."
                : error.localizedDescription
            return false
        }
    }

    private func createProfileIfNeeded(for user: User, displayName: String) async throws {
        let profile = Firestore.firestore().collection("users").document(user.uid)
        let snapshot = try await profile.getDocument()
        let name = displayName
        if !name.isEmpty, user.displayName != name {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
        }

        var values: [String: Any] = ["lastSeenAt": FieldValue.serverTimestamp()]
        if !name.isEmpty {
            values["displayName"] = name
        } else if snapshot.data()?["displayName"] as? String == "Blurb friend",
                  let authName = user.displayName,
                  !authName.isEmpty,
                  authName != "Blurb friend" {
            values["displayName"] = authName
        } else if !snapshot.exists {
            values["displayName"] = user.displayName ?? "Blurb friend"
        }
        if !snapshot.exists {
            values["profileSetupCompleted"] = false
            values["createdAt"] = FieldValue.serverTimestamp()
            if let email = user.email {
                values["email"] = email
            }
        }
        try await profile.setData(values, merge: true)
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                fatalError("Unable to generate a secure sign-in nonce.")
            }
            if Int(random) < characters.count {
                result.append(characters[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }
}
