import PhotosUI
import SwiftUI
import UIKit

struct SignedInRootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minimumLaunchTimeElapsed = false

    private var isPreparingApp: Bool {
        !minimumLaunchTimeElapsed
            || !blurbStore.profileLoaded
            || (blurbStore.profileLoaded && !blurbStore.needsProfileSetup && !blurbStore.groupsLoaded)
    }

    var body: some View {
        ZStack {
            if isPreparingApp {
                BlurbLaunchView(
                    errorMessage: blurbStore.listenerErrorMessage ?? auth.errorMessage,
                    retry: {
                        blurbStore.stop()
                        Task { await loadProfile() }
                    },
                    signOut: auth.signOut
                )
                .transition(.opacity)
            } else if blurbStore.needsProfileSetup {
                ProfileSetupView()
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: isPreparingApp)
        .task(id: auth.user?.uid) { await loadProfile() }
        .task(id: auth.user?.uid) {
            minimumLaunchTimeElapsed = reduceMotion
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(1_250))
            guard !Task.isCancelled else { return }
            minimumLaunchTimeElapsed = true
        }
    }

    private func loadProfile() async {
        guard let userID = auth.user?.uid, await auth.refreshSession() else { return }
        blurbStore.start(for: userID)
    }
}

private struct BlurbLaunchView: View {
    let errorMessage: String?
    let retry: () -> Void
    let signOut: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var detailsVisible = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("DailyBlurbLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.94)
                    .opacity(hasAppeared || reduceMotion ? 1 : 0)

                Text("DAILY BLURB")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .tracking(2)
                    .offset(y: detailsVisible || reduceMotion ? 0 : 6)
                    .opacity(detailsVisible || reduceMotion ? 1 : 0)

                if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again", action: retry)
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 1, green: 0.78, blue: 0.02))
                            .foregroundStyle(.black)
                        Button("Sign out", action: signOut)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: 300)
                } else {
                    ProgressView()
                        .tint(.secondary)
                        .opacity(detailsVisible || reduceMotion ? 1 : 0)
                        .accessibilityLabel("Opening Daily Blurb")
                }
            }
            .padding(28)
        }
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                detailsVisible = true
                return
            }
            withAnimation(.easeInOut(duration: 0.82)) {
                hasAppeared = true
            }
            withAnimation(.easeOut(duration: 0.72).delay(0.18)) {
                detailsVisible = true
            }
        }
    }
}

struct ProfileSetupView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var name = ""
    @State private var showingPhotoCropper = false
    @State private var photoData: Data?
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
                        Button { showingPhotoCropper = true } label: {
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
                                Text("Choose and crop photo")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
            .sheet(isPresented: $showingPhotoCropper) {
                CroppedProfilePhotoPicker(isPresented: $showingPhotoCropper) { croppedData in
                    photoData = croppedData
                    errorMessage = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
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
