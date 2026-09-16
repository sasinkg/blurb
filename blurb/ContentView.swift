import PhotosUI
import SwiftUI
import UIKit

#if DEBUG
struct AppStoreScreenshotContentView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let screen: String

    var body: some View {
        if screen == "feed", let group = blurbStore.groups.first {
            NavigationStack {
                GroupFeedView(group: group)
            }
        } else {
            ContentView()
        }
    }
}
#endif

private func preparedJPEG(from data: Data, maxDimension: CGFloat = 1_600) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let largestSide = max(image.size.width, image.size.height)
    guard largestSide > 0 else { return nil }
    let scale = min(1, maxDimension / largestSide)
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return resized.jpegData(compressionQuality: 0.82)
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, profile, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "newspaper"
        case .profile: return "person.text.rectangle"
        case .settings: return "slider.horizontal.3"
        }
    }

    var dockWidth: CGFloat {
        54
    }
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var selectedTab: AppTab = .home
    @State private var showingCreateGroup = false
    @State private var showingHomeAnswer = false
    @State private var showingHomeAudience = false
    @State private var homeAnswerDraft: String?
    @State private var homeImageDraft: Data?
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970

    var body: some View {
        TabView(selection: $selectedTab) {
            homeScreen
                .tabItem { Label("Home", systemImage: "newspaper") }
                .tag(AppTab.home)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.text.rectangle") }
                .tag(AppTab.profile)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .tint(.primary)
        .task(id: auth.user?.uid) {
            if let userID = auth.user?.uid {
                if await auth.refreshSession() {
                    blurbStore.start(for: userID)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { blurbStore.groupsLoaded && blurbStore.groups.isEmpty },
            set: { _ in }
        )) {
            GroupOnboardingView()
                .interactiveDismissDisabled()
        }
        .alert("Daily Blurb", isPresented: Binding(
            get: { blurbStore.errorMessage != nil || blurbStore.listenerErrorMessage != nil || auth.errorMessage != nil },
            set: {
                if !$0 {
                    blurbStore.clearPresentedErrors()
                    auth.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                blurbStore.clearPresentedErrors()
                auth.errorMessage = nil
            }
        } message: {
            Text(blurbStore.errorMessage ?? auth.errorMessage ?? blurbStore.listenerErrorMessage ?? "Please try again.")
        }
    }

    private var homeScreen: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Good morning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Your groups")
                                .font(.system(size: 36, weight: .bold, design: .serif))
                            Text("Step into a circle to answer today’s question.")
                                .foregroundStyle(.secondary)
                        }

                        HomePromptCard(prompt: todayPrompt) {
                            if blurbStore.groups.isEmpty {
                                showingCreateGroup = true
                            } else {
                                showingHomeAnswer = true
                            }
                        }

                        Text("YOUR CIRCLES")
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundStyle(.secondary)

                        if blurbStore.groups.isEmpty {
                            ContentUnavailableView(
                                "Create your first group",
                                systemImage: "person.3.fill",
                                description: Text("Groups are private spaces for the people you want to keep up with."))
                                .padding(.vertical, 48)
                        } else {
                            ForEach(blurbStore.groups) { group in
                                NavigationLink(value: group) {
                                    HomeGroupCard(group: group)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationDestination(for: BlurbGroup.self) { group in
                GroupFeedView(group: group)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreateGroup = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Create group")
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingHomeAnswer, onDismiss: offerHomeAudience) {
                NewPostView(
                    prompt: todayPrompt.question,
                    initialAnswer: nil,
                    themeSeed: todayPrompt.id,
                    requiresPhoto: todayPrompt.requiresPhoto
                ) { answer, imageData in
                    homeAnswerDraft = answer
                    homeImageDraft = imageData
                    return true
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingHomeAudience, onDismiss: clearHomeDraft) {
                HomeAudiencePicker(groups: blurbStore.groups) { selectedGroups in
                    await applyHomeAnswer(to: selectedGroups)
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .task(id: todayPrompt.id) {
                blurbStore.listenForAnswerCounts(promptID: todayPrompt.id)
            }
        }
    }

    private var todayPrompt: DailyPrompt {
        QuestionBank.prompt(
            birthdayPrompt: birthdayQuestion,
            birthday: birthdayQuestionsEnabled ? Date(timeIntervalSince1970: birthdayTimestamp) : nil
        )
    }

    private func offerHomeAudience() {
        guard homeAnswerDraft != nil || homeImageDraft != nil else { return }
        showingHomeAudience = true
    }

    private func applyHomeAnswer(to groups: [BlurbGroup]) async -> Bool {
        guard let answer = homeAnswerDraft else { return false }
        let imageData = homeImageDraft
        for group in groups {
            let succeeded: Bool
            if let existing = await blurbStore.existingAnswer(promptID: todayPrompt.id, in: group.id) {
                succeeded = await blurbStore.overwritePost(existing, answer: answer, imageData: imageData)
            } else {
                succeeded = await blurbStore.createPost(
                    answer: answer,
                    imageData: imageData,
                    prompt: todayPrompt,
                    in: group.id
                )
            }
            guard succeeded else { return false }
        }
        clearHomeDraft()
        return true
    }

    private func clearHomeDraft() {
        homeAnswerDraft = nil
        homeImageDraft = nil
    }

}

private struct HomeAudiencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let groups: [BlurbGroup]
    let apply: ([BlurbGroup]) async -> Bool
    @State private var selectedGroupIDs: Set<String>
    @State private var isApplying = false
    @State private var showingOverwriteWarning = false

    init(groups: [BlurbGroup], apply: @escaping ([BlurbGroup]) async -> Bool) {
        self.groups = groups
        self.apply = apply
        _selectedGroupIDs = State(initialValue: Set(groups.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups) { group in
                        Button {
                            if selectedGroupIDs.contains(group.id) {
                                selectedGroupIDs.remove(group.id)
                            } else {
                                selectedGroupIDs.insert(group.id)
                            }
                        } label: {
                            HStack {
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedGroupIDs.contains(group.id) ? .indigo : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Share with")
                } footer: {
                    Text("If you already answered today in a selected group, that answer will be replaced. Replies and reactions stay with the post.")
                }
            }
            .navigationTitle("Choose groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingOverwriteWarning = true
                    } label: {
                        if isApplying {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(selectedGroupIDs.isEmpty || isApplying)
                    .accessibilityLabel("Apply answer to selected groups")
                }
            }
            .confirmationDialog(
                "Apply this answer to the selected groups?",
                isPresented: $showingOverwriteWarning,
                titleVisibility: .visible
            ) {
                Button("Apply answer") { submit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing answers will be overwritten. You may lose your first-place badge because editing refreshes the timestamp, and each answer can only be edited once per day.")
            }
        }
    }

    private func submit() {
        let selectedGroups = groups.filter { selectedGroupIDs.contains($0.id) }
        isApplying = true
        Task {
            if await apply(selectedGroups) { dismiss() }
            isApplying = false
        }
    }
}

private struct HomePromptCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let prompt: DailyPrompt
    let action: () -> Void

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.78, blue: 0.02)
            : Color(red: 0.78, green: 0.56, blue: 0.02)
    }

    private var ruleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : .black
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
            Text("THE DAILY BLURB")
                .font(.caption.weight(.black))
                .tracking(2)
                .foregroundStyle(.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent)

            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption)
                .textCase(.uppercase)
                .tracking(0.8)

            Divider().overlay(Color.primary.opacity(0.35))

            Text(prompt.question)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Tap to answer")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "square.and.pencil")
                }
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background { VibrantCardBackground(seed: prompt.id) }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(ruleColor, lineWidth: 2) }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeGroupCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.78, blue: 0.02)
            : Color(red: 0.78, green: 0.56, blue: 0.02)
    }

    private var ruleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : .black
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VibrantCardBackground(seed: group.name)

            VStack(alignment: .leading, spacing: 0) {
                Text(group.name)
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent)

                Divider()
                    .overlay(Color.primary.opacity(0.35))
                    .padding(.top, 7)
                    .padding(.bottom, 10)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(blurbStore.answerCount(in: group.id))/\(group.memberCount)")
                            .font(.title.bold())
                        Text("answered today")
                            .font(.subheadline.weight(.medium))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .background(
                            colorScheme == .dark
                                ? Color(red: 1, green: 0.78, blue: 0.02)
                                : Color(red: 0.78, green: 0.56, blue: 0.02),
                            in: Circle()
                        )
                        .foregroundStyle(.black)
                }
                .foregroundStyle(.primary)
            }
            .padding(17)
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(ruleColor, lineWidth: 2) }
    }
}

private struct VibrantCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let seed: String

    var body: some View {
        ZStack {
            colorScheme == .dark
                ? Color(red: 0.14, green: 0.14, blue: 0.14)
                : Color(red: 0.985, green: 0.975, blue: 0.93)
            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 1, green: 0.78, blue: 0.02)
                        : Color(red: 0.78, green: 0.56, blue: 0.02)
                )
                .frame(width: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) {
                ForEach(0..<14, id: \.self) { _ in
                    Rectangle()
                        .fill(colorScheme == .dark ? .white.opacity(0.035) : .black.opacity(0.035))
                        .frame(height: 1)
                }
            }
        }
    }
}

private struct GroupFeedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var showingNewPost = false
    @State private var selectedPost: BlurbPost?
    @State private var postToEdit: BlurbPost?
    @State private var postToDelete: BlurbPost?
    @State private var answerToReuse: String?
    @State private var imageToReuse: Data?
    @State private var showingReuseOptions = false
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970
    let group: BlurbGroup

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Text(group.name)
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    promptCard
                    feed
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { blurbStore.select(group) }
        .sheet(isPresented: $showingNewPost, onDismiss: offerReuseIfAvailable) {
            NewPostView(
                prompt: todayPrompt.question,
                initialAnswer: nil,
                themeSeed: group.name,
                requiresPhoto: todayPrompt.requiresPhoto
            ) { answer, imageData in
                let posted = await blurbStore.createPost(answer: answer, imageData: imageData, prompt: todayPrompt, in: group.id)
                if posted {
                    answerToReuse = answer
                    imageToReuse = imageData
                }
                return posted
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $postToEdit) { post in
            NewPostView(prompt: post.prompt, initialAnswer: post.answer, themeSeed: group.name) { answer, _ in
                await blurbStore.editPost(post, answer: answer)
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedPost) { post in
            CommentsView(post: post)
                .presentationBackground(.ultraThinMaterial)
        }
        .confirmationDialog("Use this answer in another group?", isPresented: $showingReuseOptions, titleVisibility: .visible) {
            ForEach(otherGroups) { destination in
                Button(destination.name) { reuseAnswer(in: destination) }
            }
            Button("Not now", role: .cancel) { answerToReuse = nil }
        } message: {
            Text("You can reuse the same answer, or open another group later and write something different.")
        }
        .confirmationDialog(
            "Delete this answer from \(group.name)?",
            isPresented: Binding(
                get: { postToDelete != nil },
                set: { if !$0 { postToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete answer", role: .destructive) {
                guard let postToDelete else { return }
                Task { await blurbStore.deletePost(postToDelete) }
                self.postToDelete = nil
            }
            Button("Keep answer", role: .cancel) { postToDelete = nil }
        } message: {
            Text("Answers in your other groups won’t be changed.")
        }
    }

    private var promptCard: some View {
        VStack(spacing: 12) {
            Button { showingNewPost = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(todayPrompt.kind == .trivia ? "THURSDAY TRIVIA" : "TODAY'S BLURB")
                            .font(.caption.bold())
                            .tracking(1)
                            .opacity(0.8)
                        Text(todayPrompt.question)
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .multilineTextAlignment(.leading)
                    }

                    if blurbStore.hasAnswered(promptID: todayPrompt.id, in: group.id) {
                        Text("ANSWERED")
                            .font(.caption.weight(.black))
                            .tracking(1.4)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                colorScheme == .dark
                                    ? Color(red: 1, green: 0.78, blue: 0.02)
                                    : Color(red: 0.78, green: 0.56, blue: 0.02)
                            )
                    } else {
                        HStack {
                            Text("Tap to answer")
                                .font(.caption.bold())
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.headline.bold())
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background { VibrantCardBackground(seed: group.name) }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 2)
                }
            }
            .disabled(blurbStore.hasAnswered(promptID: todayPrompt.id, in: group.id))

            if let answer = blurbStore.answer(for: todayPrompt.id, in: group.id),
               blurbStore.posts.first?.id != answer.id {
                TodayAnswerCard(answer: answer)
            }
        }
        .padding(.horizontal)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TODAY IN \(group.name.uppercased())")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if !blurbStore.hasAnswered(promptID: todayPrompt.id, in: group.id) {
                ContentUnavailableView(
                    "Answer to unlock the group",
                    systemImage: "lock.fill",
                    description: Text("Post your answer here before seeing this group’s conversation."))
                    .padding(.vertical, 48)
            } else {
                ForEach(blurbStore.posts.filter { $0.promptID == todayPrompt.id }) { post in
                    PostCard(
                        post: post,
                        currentUserID: auth.user?.uid,
                        toggleLike: { Task { await blurbStore.toggleLike(post) } },
                        editAnswer: post.authorID == auth.user?.uid && post.editCount == 0 ? { postToEdit = post } : nil,
                        deleteAnswer: post.authorID == auth.user?.uid ? { postToDelete = post } : nil,
                        showComments: { selectedPost = post }
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var otherGroups: [BlurbGroup] {
        blurbStore.groups.filter { $0.id != group.id }
    }

    private var todayPrompt: DailyPrompt {
        QuestionBank.prompt(
            birthdayPrompt: birthdayQuestion,
            birthday: birthdayQuestionsEnabled ? Date(timeIntervalSince1970: birthdayTimestamp) : nil
        )
    }

    private func offerReuseIfAvailable() {
        guard answerToReuse != nil, !otherGroups.isEmpty else { return }
        showingReuseOptions = true
    }

    private func reuseAnswer(in destination: BlurbGroup) {
        guard let answerToReuse else { return }
        Task {
            _ = await blurbStore.createPost(
                answer: answerToReuse,
                imageData: imageToReuse,
                prompt: todayPrompt,
                in: destination.id
            )
            self.answerToReuse = nil
            self.imageToReuse = nil
        }
    }
}

struct PostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var blurbStore: BlurbStore
    let post: BlurbPost
    let currentUserID: String?
    let toggleLike: () -> Void
    let editAnswer: (() -> Void)?
    let deleteAnswer: (() -> Void)?
    let showComments: () -> Void

    private var previewComments: [BlurbComment] {
        Array((blurbStore.commentsByPostID[post.id] ?? []).prefix(2))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
            HStack {
                AsyncImage(url: URL(string: post.authorPhotoURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.indigo)
                }
                .font(.title)
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(post.authorName)
                            .font(.headline)

                        if let rankColor {
                            Image(systemName: "medal.fill")
                                .font(.caption)
                                .foregroundStyle(rankColor)
                                .accessibilityLabel(placementLabel ?? "Ranked answer")
                        }
                    }

                    Text(post.timeLabel)
                        .font(.subheadline)
                        .foregroundStyle(post.timeLabel == "On time" ? .green : .secondary)
                }

                Spacer()

                if editAnswer != nil || deleteAnswer != nil {
                    Menu {
                        if let editAnswer {
                            Button("Edit answer", action: editAnswer)
                        }
                        if let deleteAnswer {
                            Button("Delete answer", role: .destructive, action: deleteAnswer)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }

            Text(post.answer)
                .font(.body)

            if let imageURL = post.imageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 0) {
                Button(action: toggleLike) {
                    HStack(spacing: 5) {
                        Image(systemName: post.likeIDs.contains(currentUserID ?? "") ? "heart.fill" : "heart")
                        Text("LIKE")
                            .font(.caption2.weight(.black))
                            .tracking(0.7)
                        Text("\(post.likeCount)")
                            .font(.caption2.monospacedDigit())
                    }
                    .font(.caption)
                    .foregroundStyle(post.likeIDs.contains(currentUserID ?? "") ? .red : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1, height: 18)

                Button(action: showComments) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right.fill")
                        Text("REPLY")
                            .font(.caption2.weight(.black))
                            .tracking(0.7)
                        Text("\(post.commentCount)")
                            .font(.caption2.monospacedDigit())
                    }
                    .font(.caption)
                    .foregroundStyle(colorScheme == .dark ? Color.yellow : Color(red: 0.62, green: 0.44, blue: 0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035))
            .overlay {
                Rectangle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            }

            }
            .padding(14)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : .black, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.06), radius: 4, y: 2)
            .zIndex(1)

            if !previewComments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(previewComments) { comment in
                        CompactCommentRow(comment: comment)
                        if comment.id != previewComments.last?.id {
                            Rectangle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                    }

                    if post.commentCount > 2 {
                        Button(action: showComments) {
                            Text("View more comments")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(replyAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(commentTabFill)
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 5,
                        bottomTrailingRadius: 5,
                        topTrailingRadius: 0
                    )
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.45), lineWidth: 1)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 5,
                        bottomTrailingRadius: 5,
                        topTrailingRadius: 0
                    )
                )
                .padding(.horizontal, 10)
                .padding(.top, -2)
            }
        }
        .onAppear { blurbStore.listenForComments(on: post) }
        .onDisappear { blurbStore.stopListeningForComments(on: post.id) }
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.14)
            : Color(red: 0.995, green: 0.99, blue: 0.96)
    }

    private var replyAccent: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.78, blue: 0.02) : Color(red: 0.68, green: 0.48, blue: 0)
    }

    private var commentTabFill: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.105, blue: 0.105)
            : Color(red: 0.96, green: 0.94, blue: 0.84)
    }

    private var rankColor: Color? {
        switch currentRank {
        case 1: return Color(red: 0.92, green: 0.68, blue: 0.05)
        case 2: return Color.gray
        case 3: return Color(red: 0.65, green: 0.38, blue: 0.18)
        default: return nil
        }
    }

    private var currentRank: Int {
        blurbStore.currentAnswerRank(for: post)
    }

    private var placementLabel: String? {
        switch currentRank {
        case 1: return "1st place!"
        case 2: return "2nd place"
        case 3: return "3rd place"
        default: return nil
        }
    }
}

private struct CompactCommentRow: View {
    let comment: BlurbComment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(comment.authorName + ":")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
            Text(comment.text)
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct TodayAnswerCard: View {
    let answer: BlurbPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("TODAY'S ANSWER", systemImage: "pin.fill")
                    .font(.caption.bold())
                    .tracking(0.8)
                Spacer()
                Text("+\(answer.pointsAwarded) pts")
                    .font(.caption.bold())
            }
            .foregroundStyle(.primary)

            Text(answer.answer)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.indigo.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct GrowingAnswerField: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    private let minimumHeight: CGFloat = 58
    // A compact first line plus five additional lines before the field scrolls.
    private let maximumHeight: CGFloat = 160

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.font = bodyFont
        textView.textColor = .label
        textView.tintColor = .systemIndigo
        // Match the top and bottom inset to the line height so a single-line
        // answer sits visually centered in the compact composer.
        let verticalInset = max(0, (minimumHeight - bodyFont.lineHeight) / 2)
        textView.textContainerInset = UIEdgeInsets(
            top: verticalInset,
            left: 18,
            bottom: verticalInset,
            right: 18
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        DispatchQueue.main.async {
            textView.becomeFirstResponder()
            context.coordinator.updateHeight(for: textView)
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        DispatchQueue.main.async {
            context.coordinator.updateHeight(for: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var field: GrowingAnswerField

        init(field: GrowingAnswerField) {
            self.field = field
        }

        func textViewDidChange(_ textView: UITextView) {
            field.text = textView.text
            updateHeight(for: textView)
        }

        func updateHeight(for textView: UITextView) {
            let width = max(textView.bounds.width, 1)
            let fittingHeight = textView.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
            let newHeight = min(max(fittingHeight, field.minimumHeight), field.maximumHeight)
            textView.isScrollEnabled = fittingHeight > field.maximumHeight

            guard abs(field.height - newHeight) > 0.5 else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    self.field.height = newHeight
                }
            }
        }
    }
}

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var answer: String
    @State private var isSubmitting = false
    @State private var composerHeight: CGFloat = 58
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingEditWarning = false
    let prompt: String
    let initialAnswer: String?
    let themeSeed: String
    let requiresPhoto: Bool
    let onPost: (String, Data?) async -> Bool

    init(
        prompt: String,
        initialAnswer: String?,
        themeSeed: String,
        requiresPhoto: Bool = false,
        onPost: @escaping (String, Data?) async -> Bool
    ) {
        self.prompt = prompt
        self.initialAnswer = initialAnswer
        self.themeSeed = themeSeed
        self.requiresPhoto = requiresPhoto
        self.onPost = onPost
        _answer = State(initialValue: initialAnswer ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 20) {
                    Text(prompt)
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: promptHeight, alignment: .leading)
                        .padding(22)
                        .background { VibrantCardBackground(seed: themeSeed) }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 2)
                        }

                    if requiresPhoto {
                        VStack(spacing: 10) {
                            if let photoData, let image = UIImage(data: photoData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .clipped()
                            }

                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(photoData == nil ? "Choose a photo" : "Change photo", systemImage: "photo.on.rectangle")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        ZStack(alignment: .leading) {
                            if answer.isEmpty {
                                Text("Share your answer…")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                            }

                            GrowingAnswerField(text: $answer, height: $composerHeight)
                        }
                        .frame(height: composerHeight)
                        .background(
                            .thinMaterial,
                            in: RoundedRectangle(
                                cornerRadius: min(composerHeight / 2, 28),
                                style: .continuous
                            )
                        )

                        Button {
                            if initialAnswer == nil {
                                submitAnswer()
                            } else {
                                showingEditWarning = true
                            }
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.headline.weight(.bold))
                                }
                            }
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.02))
                            // Keep the control a soft square initially, then
                            // grow it vertically with the answer field.
                            .frame(width: 58, height: composerHeight, alignment: .center)
                            .background(
                                .black.gradient,
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                            )
                            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.36)
                        .accessibilityLabel(initialAnswer == nil ? "Post answer" : "Save edited answer")
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: composerHeight)

                    Text(initialAnswer == nil
                         ? "Once you post, your answer counts toward today’s streak."
                         : "You can edit once per day. Editing refreshes the timestamp, removes this answer from your streak, and may cost your first-place badge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Text(initialAnswer == nil ? "Answer today" : "Edit answer")
                            .font(.headline)
                        Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let original = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = preparedJPEG(from: original)
                }
            }
            .confirmationDialog(
                "Save this edit?",
                isPresented: $showingEditWarning,
                titleVisibility: .visible
            ) {
                Button("Save edit") { submitAnswer() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can only edit once per day. Editing refreshes the timestamp, so you may lose your first-place badge.")
            }
        }
    }

    private var promptHeight: CGFloat {
        max(132, 178 - (composerHeight - 58))
    }

    private var canSubmit: Bool {
        !isSubmitting
            && (!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (requiresPhoto && photoData != nil))
    }

    private func submitAnswer() {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmedAnswer.isEmpty || (requiresPhoto && photoData != nil)), !isSubmitting else { return }
        isSubmitting = true
        Task {
            if await onPost(trimmedAnswer, photoData) { dismiss() }
            isSubmitting = false
        }
    }
}

struct CommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var blurbStore: BlurbStore
    let post: BlurbPost
    @State private var newComment = ""
    @State private var isSending = false

    private var comments: [BlurbComment] {
        blurbStore.commentsByPostID[post.id] ?? []
    }

    private var accent: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.78, blue: 0.02) : Color(red: 0.78, green: 0.56, blue: 0.02)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : .black
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("THE REPLY DESK")
                                .font(.caption.weight(.black))
                                .tracking(2)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(accent)
                            Text("Comments")
                                .font(.system(size: 38, weight: .bold, design: .serif))
                            Text("Join the conversation below.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 11) {
                                ProfilePhoto(urlString: post.authorPhotoURL, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(post.authorName)
                                        .font(.system(.headline, design: .serif).bold())
                                    Text(post.timeLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1)
                            Text(post.answer)
                                .font(.system(.body, design: .serif))
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55))
                        .overlay { Rectangle().stroke(borderColor, lineWidth: 1.5) }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("REPLIES").font(.caption.weight(.black)).tracking(1.5)
                                Spacer()
                                Text("\(comments.count)").font(.caption.monospacedDigit().bold()).foregroundStyle(.secondary)
                            }
                            Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 1)
                            if comments.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(accent)
                                    Text("No replies yet")
                                        .font(.system(.title3, design: .serif).bold())
                                    Text("Be the first person to add a note.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 42)
                            } else {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment, accent: accent)
                                    if comment.id != comments.last?.id {
                                        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    TextField("Write a reply…", text: $newComment, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72))
                        .overlay { Rectangle().stroke(borderColor, lineWidth: 1.5) }

                    Button { sendComment() } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(accent)
                    }
                    .disabled(isSending || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1) }
            }
            .onAppear { blurbStore.listenForComments(on: post) }
            .onDisappear { blurbStore.stopListeningForComments(on: post.id) }
        }
    }

    private func sendComment() {
        let text = newComment
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        Task {
            if await blurbStore.addComment(text, to: post) {
                newComment = ""
            }
            isSending = false
        }
    }
}

private struct CommentRow: View {
    let comment: BlurbComment
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ProfilePhoto(urlString: comment.authorPhotoURL, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(comment.authorName)
                    .font(.system(.headline, design: .serif).bold())
                Text(comment.text)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .offset(x: -9)
        }
        .padding(.leading, 9)
    }
}

struct GroupsView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var showingCreateGroup = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Groups")
                            .font(.largeTitle.bold())

                        Text("Your circles")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        if blurbStore.groups.isEmpty {
                            ContentUnavailableView(
                                "No groups yet",
                                systemImage: "person.3.fill",
                                description: Text("Create a private space for roommates, friends, family, or anyone you want to keep up with."))
                                .padding(.vertical, 36)
                        }

                        ForEach(blurbStore.groups) { group in
                            Button {
                                blurbStore.select(group)
                            } label: {
                                GroupCard(group: group, isSelected: group.id == blurbStore.selectedGroupID)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showingCreateGroup = true
                        } label: {
                            Label("Create a group", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.indigo.opacity(0.45), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)

                        triviaSection
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var triviaSection: some View {
        let trivia = QuestionBank.weeklyTrivia()
        return HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 40, height: 40)
                .background(.indigo.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Weekly trivia")
                    .font(.headline)
                Text(trivia.question)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GroupCard: View {
    let group: BlurbGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(group.memberCount) members")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.black)
            }
        }
        .padding(13)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.black : .clear, lineWidth: 2)
        }
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var groupName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New group")
                        .font(.largeTitle.bold())

                    Text("A private place for the people you want to keep up with.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField("Name your group", text: $groupName)
                        .font(.title2.weight(.medium))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 2)
                        .frame(height: 62)

                    Button(action: createGroup) {
                        Group {
                            if isCreating {
                                ProgressView()
                                    .tint(.indigo)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .foregroundStyle(Color.indigo)
                        .frame(width: 50, height: 62)
                        .contentShape(Rectangle())
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    .opacity(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                    .accessibilityLabel("Create group")
                }

                Label("Only invited members will be able to see this group.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createGroup() {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreating = true
        Task {
            if await blurbStore.createGroup(named: name) {
                dismiss()
            }
            isCreating = false
        }
    }
}

struct FloatingDock: View {
    @Binding var selection: AppTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    ZStack {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.white.opacity(0.45))
                                .frame(width: tab.dockWidth, height: 44)
                                .matchedGeometryEffect(id: "selectedDockItem", in: namespace)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(.white.opacity(0.72), lineWidth: 1)
                                }
                                .shadow(color: .indigo.opacity(0.18), radius: 7, y: 3)
                        }

                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(selection == tab ? .indigo : .secondary)
                            .frame(width: tab.dockWidth, height: 44)
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.48), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    .indigo.opacity(0.10),
                                    .purple.opacity(0.07),
                                    .white.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.95), .white.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                }
        }
        .shadow(color: .indigo.opacity(0.12), radius: 18, y: 9)
        .shadow(color: .white.opacity(0.50), radius: 4, y: -1)
    }
}

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    private let nextReportDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.date(byAdding: .month, value: 1, to: Date.now) ?? .now) ?? .now
    @State private var showingEditProfile = false

    private var currentMonthPointsLabel: String {
        "\(Date.now.formatted(.dateTime.month(.abbreviated))) points"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 8) {
                            ProfilePhoto(urlString: blurbStore.profile.photoURL, size: 76)
                            Text(blurbStore.profile.displayName)
                                .font(.title.bold())
                            Text("Your Daily Blurb profile")
                                .foregroundStyle(.secondary)

                            Button("Edit profile") { showingEditProfile = true }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 12)

                        HStack(spacing: 12) {
                            StatCard(value: "\(blurbStore.currentStreak)", label: "day streak", icon: "flame.fill", color: .orange)
                            StatCard(value: "\(blurbStore.currentMonthPoints)", label: currentMonthPointsLabel, icon: "star.fill", color: .yellow)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("THE BADGE EDITION")
                                    .font(.caption.weight(.black))
                                    .tracking(1.4)
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color(red: 1, green: 0.78, blue: 0.02))
                                Spacer()
                                Text("ACHIEVEMENTS")
                                    .font(.caption2.bold())
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                            }

                            Divider().overlay(Color.primary.opacity(0.35))

                            BadgeRow(icon: "flame.fill", title: "On a roll", subtitle: "Answer 7 daily blurbs in a row")
                            BadgeRow(icon: "brain.head.profile", title: "Trivia ace", subtitle: "Get 5 weekly trivia answers right")
                            BadgeRow(icon: "person.3.fill", title: "Group regular", subtitle: "Share with a group 10 times")
                            if let winner = blurbStore.lastMonthWinner {
                                BadgeRow(
                                    icon: "crown.fill",
                                    title: winner.title,
                                    subtitle: "Finished first in your group with \(winner.points) points"
                                )
                            }
                        }
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 1.5)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Monthly report", systemImage: "sparkles.rectangle.stack")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                            Text("Your next private recap is scheduled for \(nextReportDate.formatted(date: .abbreviated, time: .omitted)).")
                                .foregroundStyle(.secondary)
                            Text("It will collect your newsletter-marked blurbs, group highlights, and progress toward badges.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .presentationBackground(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { auth.signOut() }
                }
            }
        }
    }
}

struct ProfilePhoto: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: urlString ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.indigo.gradient)
                .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .background(.indigo.opacity(0.10), in: Circle())
        .clipShape(Circle())
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var existingPhotoURL: String?
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Group {
                                if let photoData, let image = UIImage(data: photoData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                } else {
                                    ProfilePhoto(urlString: existingPhotoURL, size: 96)
                                }
                            }
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.indigo, in: Circle())
                                }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    TextField("Your name", text: $name)
                        .textContentType(.name)
                } header: {
                    Text("PROFILE")
                } footer: {
                    Text("Your name and photo are visible to people in your groups.")
                }
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            if await blurbStore.updateProfile(name: name, imageData: photoData) {
                                dismiss()
                            } else {
                                saveError = blurbStore.errorMessage ?? "Your profile couldn't be saved. Please try again."
                            }
                            isSaving = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                name = blurbStore.profile.displayName
                existingPhotoURL = blurbStore.profile.photoURL
            }
            .alert("Couldn't save profile", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let original = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = preparedJPEG(from: original, maxDimension: 1_024)
                }
            }
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct BadgeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Rectangle()
                    .fill(Color(red: 1, green: 0.78, blue: 0.02))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.black)
            }
            .frame(width: 43, height: 43)
            .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }

            VStack(alignment: .leading, spacing: 3) {
                Text("MILESTONE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(.headline, design: .serif).bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Color.primary.opacity(0.035))
        .overlay {
            Rectangle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : .black.opacity(0.45), lineWidth: 1)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = true
    @AppStorage("weeklyTriviaEnabled") private var weeklyTriviaEnabled = true
    @AppStorage("monthlyReportEnabled") private var monthlyReportEnabled = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var groupToRename: BlurbGroup?
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var copiedGroupName: String?
    @State private var showingDeleteAccount = false
    @State private var isDeletingAccount = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.system(size: 36, weight: .bold, design: .serif))

                        settingsCard(title: "APPEARANCE") {
                            Picker("Theme", selection: $appAppearance) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.label).tag(appearance.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        settingsCard(title: "GROUPS") {
                            if blurbStore.groups.isEmpty {
                                Text("You haven’t joined any groups yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(blurbStore.groups) { group in
                                    SettingsGroupRow(
                                        group: group,
                                        canEdit: blurbStore.canEdit(group),
                                        copyLink: {
                                            UIPasteboard.general.string = "https://blurb.app/join/\(group.inviteCode)"
                                            copiedGroupName = group.name
                                        },
                                        edit: { groupToRename = group }
                                    )
                                }
                            }

                            HStack {
                                Button { showingCreateGroup = true } label: {
                                    Label("New group", systemImage: "plus")
                                }
                                Spacer()
                                Button { showingJoinGroup = true } label: {
                                    Label("Join with code", systemImage: "number")
                                }
                            }
                            .font(.subheadline.bold())
                        }

                        settingsCard(title: "REMINDERS") {
                            Toggle("Daily Blurb reminder", isOn: $dailyReminderEnabled)
                            Toggle("Weekly Trivia", isOn: $weeklyTriviaEnabled)
                        }

                        settingsCard(title: "REPORTS") {
                            Toggle("Monthly report", isOn: $monthlyReportEnabled)
                            Text("Reports are planned to arrive a few days after each month ends.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        settingsCard(title: "PRIVACY") {
                            Label("Only members of a group can see its blurbs.", systemImage: "lock.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        settingsCard(title: "ACCOUNT") {
                            Button("Sign out") { auth.signOut() }
                                .disabled(isDeletingAccount)

                            Divider()

                            Button("Delete account", role: .destructive) {
                                showingDeleteAccount = true
                            }
                            .disabled(isDeletingAccount)

                            if isDeletingAccount {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Deleting account…")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView()
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $groupToRename) { group in
                RenameGroupView(group: group)
                    .presentationBackground(.ultraThinMaterial)
            }
            .alert("Link copied", isPresented: Binding(
                get: { copiedGroupName != nil },
                set: { if !$0 { copiedGroupName = nil } }
            )) {
                Button("OK", role: .cancel) { copiedGroupName = nil }
            } message: {
                Text("The invite link for \(copiedGroupName ?? "this group") is ready to share.")
            }
            .confirmationDialog(
                "Permanently delete your account?",
                isPresented: $showingDeleteAccount,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    isDeletingAccount = true
                    Task {
                        if await blurbStore.deleteAccountData() {
                            _ = await auth.deleteCurrentAccount()
                        }
                        isDeletingAccount = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your profile, photos, answers, and group memberships. This cannot be undone.")
            }
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SettingsGroupRow: View {
    let group: BlurbGroup
    let canEdit: Bool
    let copyLink: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(.headline, design: .serif).bold())
                Text("Code: \(group.inviteCode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: copyLink) {
                Image(systemName: "link")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Copy invite link for \(group.name)")

            Button(action: edit) {
                Image(systemName: "pencil")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(!canEdit)
            .accessibilityLabel("Rename \(group.name)")
        }
        .padding(.vertical, 6)
    }
}

private struct JoinGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var code = ""
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            Form {
                Section("INVITE CODE") {
                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Join a group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isJoining ? "Joining…" : "Join") {
                        isJoining = true
                        Task {
                            if await blurbStore.joinGroup(with: code) { dismiss() }
                            isJoining = false
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
                }
            }
        }
    }
}

private struct GroupOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(alignment: .leading, spacing: 22) {
                Text("YOU’RE IN")
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.78, blue: 0.02))

                Text("Find your people.")
                    .font(.system(size: 42, weight: .bold, design: .serif))

                Text("Daily Blurb happens inside private groups. Start a new circle or use an invite code to join one.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider().overlay(Color.primary.opacity(0.35))

                Button { showingCreateGroup = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create a group")
                                .font(.system(.title2, design: .serif).bold())
                            Text("Start a private circle and invite friends.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                    }
                    .padding(18)
                    .overlay {
                        Rectangle().stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)

                Button { showingJoinGroup = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join a group")
                                .font(.system(.title2, design: .serif).bold())
                            Text("Enter the six-character code you received.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "number")
                            .font(.title2)
                    }
                    .padding(18)
                    .overlay {
                        Rectangle().stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Use a different account") { auth.signOut() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(26)
        }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView()
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingJoinGroup) {
            JoinGroupView()
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct RenameGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var name: String
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    let group: BlurbGroup

    init(group: BlurbGroup) {
        self.group = group
        _name = State(initialValue: group.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GROUP NAME") { TextField("Group name", text: $name) }
                Section("INVITE CODE") {
                    Text(group.inviteCode).font(.body.monospaced())
                }
                Section {
                    Button("Delete group", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(isSaving || isDeleting)

                    if isDeleting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting group…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Deleting a group permanently removes it and its Daily Answers for every member.")
                }
            }
            .navigationTitle("Edit group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            if await blurbStore.updateGroup(group, name: name) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .confirmationDialog(
                "Delete \(group.name) for everyone?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete group", role: .destructive) {
                    isDeleting = true
                    Task {
                        if await blurbStore.deleteGroup(group) { dismiss() }
                        isDeleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the group, all Daily Answers, and all replies. This cannot be undone.")
            }
        }
    }
}

struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? Color(red: 0.055, green: 0.055, blue: 0.05)
            : Color(red: 0.965, green: 0.95, blue: 0.88))
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
