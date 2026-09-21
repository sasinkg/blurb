import PhotosUI
import SwiftUI
import UIKit

struct SignedInRootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore

    var body: some View {
        Group {
            if !blurbStore.profileLoaded {
                VStack(spacing: 20) {
                    if let message = blurbStore.listenerErrorMessage ?? auth.errorMessage {
                        Text(message).multilineTextAlignment(.center)
                        Button("Try again") {
                            blurbStore.stop()
                            Task { await loadProfile() }
                        }
                        Button("Sign out") { auth.signOut() }
                    } else {
                        ProgressView("Loading your profile…")
                    }
                }
                .padding()
            } else if blurbStore.needsProfileSetup {
                ProfileSetupView()
            } else {
                ContentView()
            }
        }
        .task(id: auth.user?.uid) { await loadProfile() }
    }

    private func loadProfile() async {
        guard let userID = auth.user?.uid, await auth.refreshSession() else { return }
        blurbStore.start(for: userID)
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoadingPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        // PhotosPicker's label may be evaluated outside the main actor. Capture
        // the store value here, where SwiftUI evaluates body on the main actor.
        let existingPhotoURL = blurbStore.profile.photoURL
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make yourself at home.")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    Text("Choose the name and photo your groups will see.")
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            VStack(spacing: 12) {
                                if let photoData, let image = UIImage(data: photoData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 112, height: 112)
                                        .clipShape(Circle())
                                } else {
                                    ProfilePhoto(urlString: existingPhotoURL, size: 112)
                                }
                                Text(isLoadingPhoto ? "Loading photo…" : "Choose photo")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingPhoto)
                        .accessibilityLabel("Choose profile photo")
                        Text("Photo is optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your name").font(.subheadline.weight(.medium))
                        TextField("What should we call you?", text: $name)
                            .textContentType(.name)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("profileSetupName")
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.red)
                    }

                    Button(action: save) {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : "Continue").font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isLoadingPhoto)
                    .accessibilityIdentifier("profileSetupContinue")
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { auth.signOut() }.disabled(isSaving)
                }
            }
            .onAppear {
                let existingName = blurbStore.profile.displayName
                name = existingName == "Blurb friend" ? "" : existingName
            }
            .task(id: photoItem) {
                guard let photoItem else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    guard let original = try await photoItem.loadTransferable(type: Data.self),
                          let jpeg = preparedJPEG(from: original, maxDimension: 1_024) else {
                        errorMessage = "That photo couldn't be opened. Please choose another."
                        return
                    }
                    guard !Task.isCancelled else { return }
                    photoData = jpeg
                    errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = "That photo couldn't be loaded. Please try again."
                }
            }
        }
    }

    private func save() {
        guard !isSaving, !isLoadingPhoto else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            if !(await blurbStore.updateProfile(name: name, imageData: photoData)) {
                errorMessage = blurbStore.errorMessage ?? "Your profile couldn't be saved. Please try again."
            }
        }
    }
}
