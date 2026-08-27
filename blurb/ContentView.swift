import PhotosUI
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case feed, groups, profile, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .groups: return "Groups"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "house.fill"
        case .groups: return "person.3.fill"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var dockWidth: CGFloat {
        self == .groups ? 74 : 54
    }
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var showingNewPost = false
    @State private var selectedPost: BlurbPost?
    @State private var postToEdit: BlurbPost?
    @State private var postToDelete: BlurbPost?
    @State private var selectedTab: AppTab = .feed
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970

    var body: some View {
        TabView(selection: $selectedTab) {
            feedScreen
                .tabItem { Label("Feed", systemImage: "house") }
                .tag(AppTab.feed)

            GroupsView()
            .tabItem { Label("Groups", systemImage: "person.3") }
            .tag(AppTab.groups)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.indigo)
        .task(id: auth.user?.uid) {
            if let userID = auth.user?.uid {
                blurbStore.start(for: userID)
            }
        }
        .alert("Blurb", isPresented: Binding(
            get: { blurbStore.errorMessage != nil },
            set: { if !$0 { blurbStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { blurbStore.errorMessage = nil }
        } message: {
            Text(blurbStore.errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedTab {
        case .feed:
            feedScreen
        case .groups:
            GroupsView()
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        }
    }

    private var feedScreen: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        dailyPromptButton
                        feed
                    }
                    .padding(.top)
                }
            }
            .sheet(isPresented: $showingNewPost) {
                NewPostView(prompt: todayPrompt.question, initialAnswer: nil) { answer in
                    await blurbStore.createPost(answer: answer, prompt: todayPrompt)
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $postToEdit) { post in
                NewPostView(prompt: post.prompt, initialAnswer: post.answer) { answer in
                    await blurbStore.editPost(post, answer: answer)
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedPost) { post in
                CommentsView(post: post)
                    .presentationBackground(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Delete this answer?",
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
                Text("This removes your answer from every group where you posted it.")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Good morning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(blurbStore.selectedGroup?.name ?? "Your groups")
                    .font(.title.bold())
            }

            Spacer()

            Image(systemName: "bookmark.fill")
                .foregroundStyle(.indigo)
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
        .padding(.horizontal)
    }

    private var dailyPromptButton: some View {
        VStack(spacing: 12) {
            Button {
                showingNewPost = true
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(todayPrompt.kind == .trivia
                             ? "WEDNESDAY TRIVIA"
                             : (todayPrompt.isNewsletterFeature ? "NEWSLETTER BLURB" : "TODAY'S BLURB"))
                            .font(.caption.bold())
                            .tracking(1)
                            .opacity(0.8)

                        Text(todayPrompt.question)
                            .font(.title3.bold())
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.title3.bold())
                        .padding(14)
                        .background(.white.opacity(0.22), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(22)
                .background(
                    LinearGradient(colors: [.indigo, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26)
                )
                .shadow(color: .indigo.opacity(0.35), radius: 18, y: 10)
            }
            .disabled(blurbStore.selectedGroup == nil)

            if let answer = blurbStore.answer(for: todayPrompt.id), blurbStore.posts.first?.id != answer.id {
                TodayAnswerCard(answer: answer)
            }
        }
        .padding(.horizontal)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECENT BLURBS")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if blurbStore.selectedGroup == nil {
                ContentUnavailableView(
                    "Create your first group",
                    systemImage: "person.3.fill",
                    description: Text("Groups are private spaces for the people you want to keep up with."))
                    .padding(.vertical, 48)
            } else if !blurbStore.hasAnswered(promptID: todayPrompt.id) {
                ContentUnavailableView(
                    "Answer to unlock the group",
                    systemImage: "lock.fill",
                    description: Text("Post your answer to today’s Blurb before seeing anyone else’s."))
                    .padding(.vertical, 48)
            } else {
                ForEach(blurbStore.posts) { post in
                    PostCard(
                        post: post,
                        groupName: blurbStore.selectedGroup?.name ?? "Blurb",
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

    private var todayPrompt: DailyPrompt {
        QuestionBank.prompt(
            birthdayPrompt: birthdayQuestion,
            birthday: birthdayQuestionsEnabled ? Date(timeIntervalSince1970: birthdayTimestamp) : nil
        )
    }

}

struct PostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let post: BlurbPost
    let groupName: String
    let currentUserID: String?
    let toggleLike: () -> Void
    let editAnswer: (() -> Void)?
    let deleteAnswer: (() -> Void)?
    let showComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AsyncImage(url: URL(string: post.authorPhotoURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.indigo)
                }
                .font(.largeTitle)
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(post.authorName) in \(groupName)")
                        .font(.headline)

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

            Divider().opacity(0.5)

            Text(post.prompt)
                .font(.caption.bold())
                .foregroundStyle(.indigo)

            Text(post.answer)
                .font(.body)

            if let placementLabel = post.placementLabel {
                Label(placementLabel, systemImage: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 18) {
                Button(action: toggleLike) {
                    Label("\(post.likeCount)", systemImage: post.likeIDs.contains(currentUserID ?? "") ? "heart.fill" : "heart")
                        .foregroundStyle(post.likeIDs.contains(currentUserID ?? "") ? .red : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: showComments) {
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(18)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(colorScheme == .dark ? .white.opacity(0.14) : .white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 14, y: 7)
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.08, blue: 0.13)
            : Color.white.opacity(0.82)
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
            .foregroundStyle(.indigo)

            if let placementLabel = answer.placementLabel {
                Label(placementLabel, systemImage: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

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
    @State private var answer: String
    @State private var isSubmitting = false
    @State private var composerHeight: CGFloat = 58
    let prompt: String
    let initialAnswer: String?
    let onPost: (String) async -> Bool

    init(prompt: String, initialAnswer: String?, onPost: @escaping (String) async -> Bool) {
        self.prompt = prompt
        self.initialAnswer = initialAnswer
        self.onPost = onPost
        _answer = State(initialValue: initialAnswer ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 20) {
                    Text(prompt)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: promptHeight, alignment: .leading)
                        .padding(22)
                        .background(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 26)
                        )

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

                        Button(action: submitAnswer) {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.headline.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            // Keep the control a soft square initially, then
                            // grow it vertically with the answer field.
                            .frame(width: 58, height: composerHeight, alignment: .center)
                            .background(
                                .indigo.gradient,
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                            )
                            .shadow(color: .indigo.opacity(0.25), radius: 8, y: 4)
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.36)
                        .accessibilityLabel(initialAnswer == nil ? "Post answer" : "Save edited answer")
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: composerHeight)

                    Text(initialAnswer == nil
                         ? "Once you post, your answer counts toward today’s streak."
                         : "You can edit once. Editing refreshes the timestamp and removes this answer from your streak.")
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
        }
    }

    private var promptHeight: CGFloat {
        max(132, 178 - (composerHeight - 58))
    }

    private var canSubmit: Bool {
        !isSubmitting && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitAnswer() {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            if await onPost(trimmedAnswer) { dismiss() }
            isSubmitting = false
        }
    }
}

struct CommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let post: BlurbPost
    @State private var newComment = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 18) {
                    Text("Comments on \(post.authorName)'s Blurb")
                        .font(.headline)

                    ContentUnavailableView(
                        "No comments yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Be the first roommate to respond.")
                    )

                    HStack {
                        TextField("Add a comment", text: $newComment)
                            .textFieldStyle(.roundedBorder)

                        Button("Send") {
                            newComment = ""
                        }
                        .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
                .background(.indigo, in: RoundedRectangle(cornerRadius: 13))

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
                    .foregroundStyle(.indigo)
            }
        }
        .padding(13)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.indigo : .clear, lineWidth: 2)
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
                            Text("Your Blurb profile")
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
                            Text("BADGES")
                                .font(.caption.bold())
                                .tracking(1)
                                .foregroundStyle(.secondary)

                            BadgeRow(icon: "flame.fill", color: .orange, title: "On a roll", subtitle: "Answer 7 daily blurbs in a row")
                            BadgeRow(icon: "brain.head.profile", color: .purple, title: "Trivia ace", subtitle: "Get 5 weekly trivia answers right")
                            BadgeRow(icon: "person.3.fill", color: .blue, title: "Group regular", subtitle: "Share with a group 10 times")
                            if let winner = blurbStore.lastMonthWinner {
                                BadgeRow(
                                    icon: "crown.fill",
                                    color: .yellow,
                                    title: winner.title,
                                    subtitle: "Finished first in your group with \(winner.points) points"
                                )
                            }
                        }
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))

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
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ProfilePhoto(urlString: blurbStore.profile.photoURL, size: 96)
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
                            }
                            isSaving = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear { name = blurbStore.profile.displayName }
            .onChange(of: photoItem) { _, item in
                Task { photoData = try? await item?.loadTransferable(type: Data.self) }
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
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = true
    @AppStorage("weeklyTriviaEnabled") private var weeklyTriviaEnabled = true
    @AppStorage("monthlyReportEnabled") private var monthlyReportEnabled = true

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.title.bold())

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
                    }
                    .padding()
                }
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

struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.02, green: 0.025, blue: 0.06),
                    Color(red: 0.065, green: 0.04, blue: 0.15),
                    Color(red: 0.015, green: 0.02, blue: 0.05)
                ]
                : [
                    Color.white,
                    Color.indigo.opacity(0.04),
                    Color.white
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
