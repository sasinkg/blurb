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

func preparedJPEG(from data: Data, maxDimension: CGFloat = 1_600) -> Data? {
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
    @State private var dailyPromptClock = Date.now
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
        .task {
            while !Task.isCancelled {
                dailyPromptClock = .now
                try? await Task.sleep(for: .seconds(60))
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
                            if !blurbStore.groups.isEmpty {
                                let answered = blurbStore.groups.filter { blurbStore.myAnswerStatusByGroup[$0.id] == true }.count
                                let loaded = blurbStore.groups.allSatisfy { blurbStore.myAnswerStatusByGroup[$0.id] != nil }
                                Text(loaded ? "\(answered)/\(blurbStore.groups.count) groups answered today" : "Checking today's answers…")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
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
                    requiresPhoto: todayPrompt.requiresPhoto,
                    pollOptions: todayPrompt.pollOptions
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
        if blurbStore.canAddReviewExamples {
            return ExampleGroupContent.prompt(for: dailyPromptClock)
        }
        return QuestionBank.prompt(
            for: dailyPromptClock,
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
                HStack(spacing: 8) {
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

                    Spacer(minLength: 0)
                    if let answered = blurbStore.myAnswerStatusByGroup[group.id] {
                        Image(systemName: answered ? "checkmark" : "circle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                            .accessibilityLabel(answered ? "You answered today" : "You have not answered today")
                    }
                }

                Divider()
                    .overlay(Color.primary.opacity(0.35))
                    .padding(.top, 7)
                    .padding(.bottom, 10)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(blurbStore.displayedAnswerCount(in: group))/\(group.displayedParticipantCount)")
                            .font(.title.bold())
                        Text(group.isExample ? "today · includes \(group.sampleParticipantCount) examples" : "answered today")
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
    @State private var dailyPromptClock = Date.now
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970
    let group: BlurbGroup

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    Text(group.name)
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    if group.isExample {
                        Text("EXAMPLE GROUP · Includes three fictional participants: Maya, Jordan, and Sam. Answer today’s prompt to unlock their sample conversations. Likes and replies you add are saved in this private group.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    promptCard(proxy: proxy)
                    feed
                }
                .padding(.vertical)
            }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GroupNewsletterHomeView(group: group)
                } label: {
                    Image(systemName: "newspaper.fill")
                }
                .accessibilityLabel("\(group.name) newsletter")
            }
        }
        .onAppear { blurbStore.select(group) }
        .onChange(of: blurbStore.hasAnswered(promptID: todayPrompt.id, in: group.id)) { _, answered in
            if !answered {
                selectedPost = nil
                postToEdit = nil
            }
        }
        .task {
            while !Task.isCancelled {
                dailyPromptClock = .now
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(isPresented: $showingNewPost, onDismiss: offerReuseIfAvailable) {
            NewPostView(
                prompt: todayPrompt.question,
                initialAnswer: nil,
                themeSeed: group.name,
                requiresPhoto: todayPrompt.requiresPhoto,
                pollOptions: todayPrompt.pollOptions
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
            NewPostView(prompt: post.prompt, initialAnswer: post.answer, themeSeed: group.name, pollOptions: post.pollOptions) { answer, _ in
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

    private func promptCard(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
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
            .zIndex(1)

            if let answer = blurbStore.answer(for: todayPrompt.id, in: group.id) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(answer.id, anchor: .top)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("GO TO MY ANSWER")
                            .tracking(0.8)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Color.primary.opacity(0.05))
                    .overlay {
                        UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                            .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .accessibilityLabel("Go to my answer")
            }

        }
        .padding(.horizontal)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(group.isExample ? "EXAMPLE CONVERSATIONS" : "TODAY IN \(group.name.uppercased())")
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
                ForEach(blurbStore.posts.filter { $0.groupID == group.id && ($0.promptID == todayPrompt.id || (group.isExample && $0.isSample)) }) { post in
                    PostCard(
                        post: post,
                        currentUserID: auth.user?.uid,
                        toggleLike: { Task { await blurbStore.toggleLike(post) } },
                        editAnswer: !post.isSample && post.authorID == auth.user?.uid ? { postToEdit = post } : nil,
                        deleteAnswer: !post.isSample && post.authorID == auth.user?.uid ? { postToDelete = post } : nil,
                        showComments: { selectedPost = post }
                    )
                    .id(post.id)
                }
            }
        }
        .padding(.horizontal)
    }

    private var otherGroups: [BlurbGroup] {
        blurbStore.groups.filter { $0.id != group.id }
    }

    private var todayPrompt: DailyPrompt {
        if blurbStore.canAddReviewExamples {
            return ExampleGroupContent.prompt(for: dailyPromptClock)
        }
        return QuestionBank.prompt(
            for: dailyPromptClock,
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
    @State private var showingPostEditor = false

    private var previewComments: [BlurbComment] {
        Array((blurbStore.commentsByPostID[post.id] ?? []).prefix(2))
    }

    private var badgeProgress: [AchievementProgress] {
        post.isSample ? [] : blurbStore.achievements(for: post.authorID, in: post.groupID)
    }

    private var hasEarnedBadges: Bool {
        badgeProgress.contains { $0.earned != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: hasEarnedBadges ? .top : .center, spacing: 12) {
                ProfilePhoto(urlString: post.authorPhotoURL, size: 38)
                    .fixedSize()

                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(memberNameText(post.authorName, userID: post.isSample ? nil : post.authorID))
                                .font(.headline)
                                .fixedSize(horizontal: true, vertical: false)
                            postMetadata
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memberNameText(post.authorName, userID: post.isSample ? nil : post.authorID))
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            postMetadata
                        }
                    }
                    if hasEarnedBadges {
                        EarnedBadges(progress: badgeProgress)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if editAnswer != nil || deleteAnswer != nil {
                    Menu {
                        if editAnswer != nil {
                            Button("Edit answer") { showingPostEditor = true }
                        }
                        if let deleteAnswer {
                            Button("Delete answer", role: .destructive, action: deleteAnswer)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }

            if post.isSample {
                Text("SAMPLE · \(ExampleGroupContent.question)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(mentionText(post.answer))
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

            HStack(spacing: 18) {
                Button(action: toggleLike) {
                    HStack(spacing: 6) {
                        Image(systemName: post.likeIDs.contains(currentUserID ?? "") ? "heart.fill" : "heart")
                        Text("\(post.likeCount)").font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(post.likeIDs.contains(currentUserID ?? "") ? .red : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(post.likeIDs.contains(currentUserID ?? "") ? "Unlike answer" : "Like answer")
                .accessibilityValue("\(post.likeCount) likes")

                Button(action: showComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                        Text("\(post.commentCount)").font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(replyAccent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Open replies")
                .accessibilityValue("\(post.commentCount) replies")
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .padding(.vertical, -6)

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
                        CompactCommentRow(comment: comment, post: post)
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
                .padding(.top, 4)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(commentTabFill)
                .contentShape(Rectangle())
                .onTapGesture(perform: showComments)
                .accessibilityAction(named: "Open all replies", showComments)
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
        .sheet(isPresented: $showingPostEditor) {
            PostAnswerEditor(post: post)
        }
        .modifier(MemberProfileLinks(groupID: post.groupID))
    }

    private var postMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let rankColor {
                Label(placementLabel ?? "", systemImage: "medal.fill")
                    .foregroundStyle(rankColor)
                    .accessibilityLabel(placementLabel ?? "Ranked answer")
            }
            Text(post.timeLabel)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .fixedSize(horizontal: true, vertical: false)
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
        case 4...: return .secondary
        default: return nil
        }
    }

    private var currentRank: Int {
        blurbStore.currentAnswerRank(for: post)
    }

    private var placementLabel: String? {
        switch currentRank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4...:
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            return formatter.string(from: NSNumber(value: currentRank))
        default: return nil
        }
    }
}

private struct CompactCommentRow: View {
    let comment: BlurbComment
    let post: BlurbPost

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
        (Text(memberNameText(comment.authorName + ": ", userID: comment.authorID)).bold() + Text(mentionText(comment.text)))
            .font(.caption2)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
            ReplyLikeButton(comment: comment, post: post, compact: true)
        }
        .modifier(OwnReplyActions(comment: comment, post: post))
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
        let keyboardToolbar = UIToolbar()
        keyboardToolbar.sizeToFit()
        keyboardToolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", style: .done, target: textView,
                            action: #selector(UIResponder.resignFirstResponder))
        ]
        textView.inputAccessoryView = keyboardToolbar
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        DispatchQueue.main.async {
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
    @EnvironmentObject private var blurbStore: BlurbStore
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
    let pollOptions: [String]
    let onPost: (String, Data?) async -> Bool

    init(
        prompt: String,
        initialAnswer: String?,
        themeSeed: String,
        requiresPhoto: Bool = false,
        pollOptions: [String] = [],
        onPost: @escaping (String, Data?) async -> Bool
    ) {
        self.prompt = prompt
        self.initialAnswer = initialAnswer
        self.themeSeed = themeSeed
        self.requiresPhoto = requiresPhoto
        self.pollOptions = pollOptions
        self.onPost = onPost
        _answer = State(initialValue: initialAnswer ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                VStack(spacing: 16) {
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

                    if pollOptions.isEmpty {
                    MentionSuggestions(text: $answer, names: blurbStore.mentionNames())
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
                    } else {
                        VStack(spacing: 10) {
                            ForEach(pollOptions, id: \.self) { option in
                                Button {
                                    answer = option
                                } label: {
                                    HStack {
                                        Text(option)
                                            .font(.headline)
                                        Spacer()
                                        Image(systemName: answer == option ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(15)
                                    .background(
                                        answer == option
                                            ? Color(red: 1, green: 0.78, blue: 0.02).opacity(0.34)
                                            : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button(initialAnswer == nil ? "Submit vote" : "Save vote") {
                                if initialAnswer == nil {
                                    submitAnswer()
                                } else {
                                    showingEditWarning = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black)
                            .disabled(!canSubmit)
                        }
                    }

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
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(initialAnswer == nil ? "Post" : "Save") {
                        if initialAnswer == nil { submitAnswer() }
                        else { showingEditWarning = true }
                    }
                    .disabled(!canSubmit)
                }
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
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("The reply desk")
                                .font(.system(.title2, design: .serif).bold())
                            Spacer()
                            Text("\(comments.count) \(comments.count == 1 ? "REPLY" : "REPLIES")")
                                .font(.caption2.weight(.black))
                                .tracking(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .foregroundStyle(.black)
                                .background(Color(red: 1, green: 0.78, blue: 0.02))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("IN RESPONSE TO")
                                .font(.system(.caption2, design: .serif).weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 11) {
                                ProfilePhoto(urlString: post.authorPhotoURL, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(memberNameText(post.authorName, userID: post.isSample ? nil : post.authorID))
                                        .font(.system(.subheadline, design: .serif).bold())
                                    Text(post.timeLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(mentionText(post.answer))
                                .font(.system(.subheadline, design: .serif))
                                .lineSpacing(2)
                            if let imageURL = post.imageURL {
                                AsyncImage(url: URL(string: imageURL)) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: { ProgressView() }
                                .frame(maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55))
                        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 6) {
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
                                .padding(.vertical, 24)
                            } else {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment, post: post, accent: accent)
                                    if comment.id != comments.last?.id {
                                        Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1).padding(.leading, 43)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    MentionSuggestions(text: $newComment, names: blurbStore.mentionNames(in: post.groupID))
                HStack(spacing: 10) {
                    TextField("Write a reply…", text: $newComment, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.16), lineWidth: 1) }

                    Button { sendComment() } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "arrow.up")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel("Send reply")
                    .disabled(isSending || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1) }
                }
            }
            .onAppear { blurbStore.listenForComments(on: post) }
            .onDisappear { blurbStore.stopListeningForComments(on: post.id) }
        }
        .modifier(MemberProfileLinks(groupID: post.groupID))
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
    @EnvironmentObject private var auth: AuthManager
    @State private var editing = false
    let comment: BlurbComment
    let post: BlurbPost
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ProfilePhoto(urlString: comment.authorPhotoURL, size: 32)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(memberNameText(comment.authorName, userID: comment.authorID))
                        .font(.system(.subheadline, design: .serif).bold())
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if comment.authorID == auth.user?.uid {
                        Button { editing = true } label: { Image(systemName: "pencil") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit reply")
                    }
                    ReplyLikeButton(comment: comment, post: post)
                }
                Text(mentionText(comment.text))
                    .font(.system(.subheadline, design: .serif))
                    .lineSpacing(1)
            }
        }
        .padding(.vertical, 2)
        .padding(.vertical, 3)
        .sheet(isPresented: $editing) { EditReplyView(comment: comment, post: post) }
        .modifier(OwnReplyActions(comment: comment, post: post))
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

                Text(group.isExample
                     ? "\(group.displayedParticipantCount) participants · \(group.sampleParticipantCount) examples"
                     : "\(group.memberCount) members")
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

                            Text("Progress in \(blurbStore.selectedGroup?.name ?? "your group")")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(blurbStore.myAchievements) { progress in
                                AchievementRow(progress: progress)
                            }
                            if let winner = blurbStore.lastMonthWinner {
                                BadgeRow(
                                    icon: "crown.fill",
                                    title: winner.title,
                                    subtitle: "Finished first in your group with \(winner.points) points",
                                    earned: true
                                )
                            }
                        }
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : .black, lineWidth: 1.5)
                        }

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
        .fixedSize()
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
    var earned = false

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
            Image(systemName: earned ? "checkmark.seal.fill" : "lock.fill")
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
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("replyNotificationsEnabled") private var replyNotificationsEnabled = false
    @AppStorage("weeklyTriviaEnabled") private var weeklyTriviaEnabled = true
    @AppStorage("monthlyReportEnabled") private var monthlyReportEnabled = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var groupToRename: BlurbGroup?
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var copiedGroupName: String?
    @State private var copiedItem = "Link"
    @State private var showingDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var reminderErrorMessage: String?

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
                                            copiedItem = "Link"
                                            copiedGroupName = group.name
                                        },
                                        copyCode: {
                                            UIPasteboard.general.string = group.inviteCode
                                            copiedItem = "Code"
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

                        if blurbStore.canAddReviewExamples {
                            settingsCard(title: "REVIEW EXAMPLES") {
                                AddExampleGroupButton()
                                Text("Add a private example group with fictional answers and replies.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        settingsCard(title: "REMINDERS") {
                            Toggle("Daily Blurb reminder", isOn: $dailyReminderEnabled)
                                .onChange(of: dailyReminderEnabled) { _, enabled in
                                    updateDailyReminder(enabled: enabled)
                                }
                            Text("Get a reminder every day at 7:00 PM.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Weekly Trivia", isOn: $weeklyTriviaEnabled)
                            Toggle("Replies and @mentions", isOn: $replyNotificationsEnabled)
                                .onChange(of: replyNotificationsEnabled) { _, enabled in
                                    updateReplyNotifications(enabled: enabled)
                                }
                        }

                        settingsCard(title: "REPORTS") {
                            Toggle("Monthly report", isOn: $monthlyReportEnabled)
                            Text("Reports are planned to arrive a few days after each month ends.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                            NavigationLink {
                                DemoMonthlyNewsletterView(
                                    displayName: blurbStore.profile.displayName,
                                    groupName: blurbStore.selectedGroup?.name ?? "Roomies"
                                )
                            } label: {
                                Label("Open demo newsletter", systemImage: "newspaper.fill")
                                    .font(.subheadline.bold())
                            }
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
            .alert("\(copiedItem) copied", isPresented: Binding(
                get: { copiedGroupName != nil },
                set: { if !$0 { copiedGroupName = nil } }
            )) {
                Button("OK", role: .cancel) { copiedGroupName = nil }
            } message: {
                Text("The invite \(copiedItem.lowercased()) for \(copiedGroupName ?? "this group") is ready to share.")
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
            .alert("Daily reminder", isPresented: Binding(
                get: { reminderErrorMessage != nil },
                set: { if !$0 { reminderErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { reminderErrorMessage = nil }
            } message: {
                Text(reminderErrorMessage ?? "Please try again.")
            }
            .task {
                guard dailyReminderEnabled else { return }
                let restored = await NotificationManager.shared.restoreDailyReminderIfAuthorized()
                if !restored {
                    dailyReminderEnabled = false
                }
            }
            .task {
                guard replyNotificationsEnabled else { return }
                let restored = await NotificationManager.shared.restoreReplyNotificationsIfAuthorized()
                if !restored {
                    replyNotificationsEnabled = false
                }
            }
        }
    }

    private func updateDailyReminder(enabled: Bool) {
        if enabled {
            Task {
                do {
                    try await NotificationManager.shared.enableDailyReminder()
                } catch {
                    dailyReminderEnabled = false
                    reminderErrorMessage = error.localizedDescription
                }
            }
        } else {
            NotificationManager.shared.disableDailyReminder()
        }
    }

    private func updateReplyNotifications(enabled: Bool) {
        guard enabled else {
            Task { await NotificationManager.shared.disableReplyNotifications() }
            return
        }
        Task {
            do {
                try await NotificationManager.shared.enableReplyNotifications()
            } catch {
                replyNotificationsEnabled = false
                reminderErrorMessage = error.localizedDescription
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
    let copyCode: () -> Void
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
            Menu {
                Button("Copy group code", systemImage: "number", action: copyCode)
                Button("Copy invite link", systemImage: "link", action: copyLink)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Share \(group.name)")

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
    @EnvironmentObject private var blurbStore: BlurbStore
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

                if blurbStore.canAddReviewExamples {
                    AddExampleGroupButton()
                        .font(.headline)
                        .padding(.vertical, 8)
                }

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


private struct EarnedBadgeLabel: View {
    let tier: AchievementTier
    @ScaledMetric(relativeTo: .caption2) private var textSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 4) {
            AnimatedBadgeIcon(systemName: tier.icon)
            Text(tier.title.uppercased())
                .tracking(0.5)
        }
        .font(.system(size: textSize, weight: .black, design: .serif))
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(red: 1, green: 0.78, blue: 0.02))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.title)
    }
}

private struct EarnedBadges: View {
    let progress: [AchievementProgress]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(progress.filter { $0.earned != nil }) { item in
                    EarnedBadgeLabel(tier: item.earned!)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(progress.filter { $0.earned != nil }) { item in
                    EarnedBadgeLabel(tier: item.earned!)
                }
            }
        }
    }
}

private struct AchievementRow: View {
    let progress: AchievementProgress
    var body: some View {
        let tier = progress.earned ?? progress.tiers[0]
        let color = Color(red: 1, green: 0.78, blue: 0.02)
        HStack(spacing: 12) {
            AnimatedBadgeIcon(systemName: tier.icon, enabled: progress.earned != nil)
                .font(.title2.bold())
                .frame(width: 48, height: 48)
                .background(color, in: Rectangle())
                .foregroundStyle(.black)
                .overlay(alignment: .bottomTrailing) {
                    if let rank = progress.earnedIndex {
                        Text("\(rank + 1)").font(.caption2.bold())
                            .padding(3).background(.regularMaterial, in: Circle())
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(tier.title).font(.headline)
                if let next = progress.next {
                    Text("\(progress.value)/\(next.threshold) \(progress.unit) · Next: \(next.title)")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.value), total: Double(next.threshold)).tint(color)
                } else {
                    Text("Top rank · \(progress.value) \(progress.unit)").font(.caption)
                }
            }
            Image(systemName: progress.earned == nil ? "lock.fill" : "checkmark.seal.fill")
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }
}

private struct MentionSuggestions: View {
    @Binding var text: String
    let names: [String]
    private var query: String? {
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).last,
              !text.hasSuffix(" "), !text.hasSuffix("\n"), token.hasPrefix("@") else { return nil }
        return String(token.dropFirst())
    }
    var body: some View {
        if let query {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(names.filter {
                        query.isEmpty || $0.lowercased().hasPrefix(query.lowercased())
                    }, id: \.self) { name in
                        Button {
                            guard let range = text.range(of: "@", options: .backwards) else { return }
                            let firstName = name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name
                            text.replaceSubrange(range.lowerBound..., with: "@" + firstName + " ")
                        } label: {
                            Text("@" + name).font(.caption.bold()).padding(8)
                                .background(.blue.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .accessibilityLabel("Mention someone by first name")
        }
    }
}


private func mentionText(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])@[\\p{L}\\p{M}][\\p{L}\\p{M}\\p{N}_’-]*") else { return result }
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let range = Range(match.range, in: text),
              let attributedRange = Range(range, in: result) else { continue }
        result[attributedRange].link = memberURL(kind: "mention", value: String(text[range].dropFirst()))
        result[attributedRange].foregroundColor = .blue
        result[attributedRange].inlinePresentationIntent = .stronglyEmphasized
    }
    return result
}


private func memberURL(kind: String, value: String) -> URL? {
    var components = URLComponents()
    components.scheme = "blurb-member"
    components.host = kind
    components.queryItems = [URLQueryItem(name: "value", value: value)]
    return components.url
}

private func memberNameText(_ name: String, userID: String?) -> AttributedString {
    var text = AttributedString(name)
    if let userID {
        text.link = memberURL(kind: "id", value: userID)
        text.foregroundColor = .primary
    }
    return text
}

private struct MemberProfileRoute: Identifiable {
    let id = UUID()
    let memberID: String?
    let firstName: String?
}

private struct MemberProfileLinks: ViewModifier {
    let groupID: String
    @State private var route: MemberProfileRoute?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "blurb-member",
                      let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "value" })?.value else {
                    return .systemAction
                }
                route = MemberProfileRoute(memberID: url.host == "id" ? value : nil,
                                           firstName: url.host == "mention" ? value : nil)
                return .handled
            })
            .sheet(item: $route) { route in
                MemberProfileSheet(groupID: groupID, route: route)
            }
    }
}

private struct MemberProfileSheet: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    @Environment(\.dismiss) private var dismiss
    let groupID: String
    let route: MemberProfileRoute
    @State private var selectedMember: GroupMemberProfile?
    @State private var expandedPhoto = false

    private var matches: [GroupMemberProfile] {
        blurbStore.memberProfiles(in: groupID).filter { member in
            if let id = route.memberID { return member.id == id }
            let firstName = member.name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? member.name
            return firstName.compare(route.firstName ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                if let member = selectedMember ?? (matches.count == 1 ? matches.first : nil) {
                    ScrollView {
                        VStack(spacing: 18) {
                            Button { expandedPhoto = true } label: {
                                ProfilePhoto(urlString: member.photoURL, size: 100)
                            }
                            .buttonStyle(.plain)
                            .disabled(member.photoURL == nil)
                            .accessibilityLabel("Enlarge \(member.name)'s profile photo")
                            Text(member.name).font(.system(.title, design: .serif).bold())
                            Text(blurbStore.groups.first { $0.id == groupID }?.name ?? "Group member")
                                .foregroundStyle(.secondary)
                            let progress = blurbStore.achievements(for: member.id, in: groupID)
                            EarnedBadges(progress: progress)
                            if progress.allSatisfy({ $0.earned == nil }) {
                                Text("No badges earned yet").font(.subheadline).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text("GROUP ACHIEVEMENTS").font(.caption.bold()).tracking(1)
                                ForEach(progress) { item in AchievementRow(progress: item) }
                            }
                            .padding(16)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(24)
                    }
                    .sheet(isPresented: $expandedPhoto) {
                        NavigationStack {
                            AsyncImage(url: URL(string: member.photoURL ?? "")) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { ProgressView() }
                            .padding()
                            .navigationTitle(member.name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { expandedPhoto = false }
                                }
                            }
                        }
                    }
                } else if matches.isEmpty {
                    ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("This name could not be matched to a current member's shared answers or replies in this group."))
                } else {
                    List(matches) { member in
                        Button { selectedMember = member } label: {
                            HStack(spacing: 12) {
                                ProfilePhoto(urlString: member.photoURL, size: 38)
                                Text(member.name).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(matches.count > 1 && selectedMember == nil ? "Who did you mean?" : "Member profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}


private struct ReplyLikeButton: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var updating = false
    let comment: BlurbComment
    let post: BlurbPost
    var compact = false
    private var liked: Bool { comment.likeIDs.contains(auth.user?.uid ?? "") }

    var body: some View {
        Button {
            updating = true
            Task {
                await blurbStore.toggleCommentLike(comment, on: post)
                updating = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                Text("\(comment.likeIDs.count)").monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(liked ? .red : .secondary)
            .frame(minWidth: compact ? 32 : 44, minHeight: compact ? 22 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updating || auth.user == nil)
        .accessibilityLabel(liked ? "Unlike reply" : "Like reply")
        .accessibilityValue("\(comment.likeIDs.count) likes")
    }
}


/// Animate only the glyph so the compact badge and text never shift layout.
private struct AnimatedBadgeIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = true
    let systemName: String
    var enabled = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0,
                                paused: !enabled || reduceMotion || !visible || scenePhase != .active)) { context in
            let moving = enabled && !reduceMotion && visible && scenePhase == .active
            let time = moving ? context.date.timeIntervalSinceReferenceDate : 0
            let flame = systemName.contains("flame")
            let wave = moving ? sin(time * (flame ? 4.5 : 2.0)) : 0
            Image(systemName: systemName)
                .scaleEffect(x: 1 + wave * (flame ? 0.035 : 0.025),
                             y: 1 + wave * (flame ? 0.07 : 0.025), anchor: .bottom)
                .rotationEffect(.degrees(wave * (flame ? 2 : 1)))
                .offset(y: flame ? -abs(wave) * 0.6 : 0)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .accessibilityHidden(true)
    }
}


private struct EditReplyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let comment: BlurbComment
    let post: BlurbPost
    @State private var draft: String
    @State private var saving = false
    @State private var saveError: String?

    init(comment: BlurbComment, post: BlurbPost) {
        self.comment = comment
        self.post = post
        _draft = State(initialValue: comment.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Your reply", text: $draft, axis: .vertical).lineLimit(3...10)
                MentionSuggestions(text: $draft, names: blurbStore.mentionNames(in: post.groupID))
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .navigationTitle("Edit reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if await blurbStore.editComment(comment, on: post, text: draft) { dismiss() }
                            else { saveError = blurbStore.errorMessage ?? "Could not save your reply." }
                            saving = false
                        }
                    }
                    .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1000)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}


private struct OwnReplyActions: ViewModifier {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var confirmingDelete = false
    let comment: BlurbComment
    let post: BlurbPost
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    if comment.authorID == auth.user?.uid { confirmingDelete = true }
                }
            )
            .contextMenu {
                if comment.authorID == auth.user?.uid {
                    Button("Delete reply", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            .confirmationDialog("Delete your reply?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete reply", role: .destructive) {
                    Task { await blurbStore.deleteComment(comment, on: post) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

private struct PostAnswerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let post: BlurbPost
    @State private var draft: String
    @State private var saving = false
    @State private var saveError: String?
    init(post: BlurbPost) {
        self.post = post
        _draft = State(initialValue: post.answer)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(post.prompt) }
                Section("Your answer") {
                    if post.pollOptions.isEmpty {
                        TextField("Your answer", text: $draft, axis: .vertical).lineLimit(3...12)
                    } else {
                        Picker("Answer", selection: $draft) {
                            ForEach(post.pollOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    MentionSuggestions(text: $draft, names: blurbStore.mentionNames(in: post.groupID))
                }
                Text("Edit your text without changing the attached photo. Saving refreshes your timestamp and removes this answer's streak credit.")
                    .font(.caption).foregroundStyle(.secondary)
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .navigationTitle("Edit answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if await blurbStore.editPost(post, answer: draft) { dismiss() }
                            else { saveError = blurbStore.errorMessage ?? "Couldn't save this answer." }
                            saving = false
                        }
                    }
                    .disabled(saving || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && post.imageURL == nil))
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}
