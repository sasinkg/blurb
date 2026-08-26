import SwiftUI

struct BlurbPost: Identifiable {
    let id = UUID()
    let author: String
    let timeLabel: String
    let answer: String
    var likeCount: Int
    var commentCount: Int
    var isLiked = false

    static let samples = [
        BlurbPost(
            author: "Jenna",
            timeLabel: "4 hours late",
            answer: "Starting to love the summer weather. It feels like my seasonal depression is gone!",
            likeCount: 4,
            commentCount: 2
        ),
        BlurbPost(
            author: "Daniel",
            timeLabel: "2 hours late",
            answer: "I slept in until 11 am.",
            likeCount: 6,
            commentCount: 18
        ),
        BlurbPost(
            author: "Oscar",
            timeLabel: "On time",
            answer: "I finally cleaned the kitchen and made coffee before class.",
            likeCount: 3,
            commentCount: 1
        )
    ]
}

struct BlurbGroup: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let memberCount: Int

    static let samples = [
        BlurbGroup(name: "College Roommates", memberCount: 4),
        BlurbGroup(name: "Sunday Dinner", memberCount: 6),
        BlurbGroup(name: "High School Friends", memberCount: 8)
    ]
}

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
    @State private var showingNewPost = false
    @State private var selectedPost: BlurbPost?
    @State private var selectedTab: AppTab = .feed
    @State private var posts = BlurbPost.samples
    @State private var groups = BlurbGroup.samples
    @State private var selectedGroup = BlurbGroup.samples[0]
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970

    var body: some View {
        TabView(selection: $selectedTab) {
            feedScreen
                .tabItem { Label("Feed", systemImage: "house") }
                .tag(AppTab.feed)

            GroupsView(
                groups: $groups,
                selectedGroup: $selectedGroup,
                birthdayQuestionsEnabled: $birthdayQuestionsEnabled,
                birthdayQuestion: $birthdayQuestion,
                birthdayTimestamp: $birthdayTimestamp
            )
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
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedTab {
        case .feed:
            feedScreen
        case .groups:
            GroupsView(
                groups: $groups,
                selectedGroup: $selectedGroup,
                birthdayQuestionsEnabled: $birthdayQuestionsEnabled,
                birthdayQuestion: $birthdayQuestion,
                birthdayTimestamp: $birthdayTimestamp
            )
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
                NewPostView(prompt: todayPrompt.question) { answer in
                    posts.insert(
                        BlurbPost(
                            author: "You",
                            timeLabel: "Just now",
                            answer: answer,
                            likeCount: 0,
                            commentCount: 0
                        ),
                        at: 0
                    )
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedPost) { post in
                CommentsView(post: post)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Good morning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(selectedGroup.name)
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
        Button {
            showingNewPost = true
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(todayPrompt.isNewsletterFeature ? "NEWSLETTER BLURB" : "TODAY'S BLURB")
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
                LinearGradient(
                    colors: [.indigo, .purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .shadow(color: .indigo.opacity(0.35), radius: 18, y: 10)
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

            ForEach(posts) { post in
                PostCard(
                    post: post,
                    groupName: selectedGroup.name,
                    toggleLike: { toggleLike(for: post.id) },
                    showComments: { selectedPost = post }
                )
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

    private func toggleLike(for id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].isLiked.toggle()
        posts[index].likeCount += posts[index].isLiked ? 1 : -1
    }
}

struct PostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let post: BlurbPost
    let groupName: String
    let toggleLike: () -> Void
    let showComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(post.author) in \(groupName)")
                        .font(.headline)

                    Text(post.timeLabel)
                        .font(.subheadline)
                        .foregroundStyle(post.timeLabel == "On time" ? .green : .secondary)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            Text("Answering today's blurb")
                .font(.caption.bold())
                .foregroundStyle(.indigo)

            Text(post.answer)
                .font(.body)

            HStack(spacing: 18) {
                Button(action: toggleLike) {
                    Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(post.isLiked ? .red : .secondary)
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

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    let prompt: String
    let onPost: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                VStack(spacing: 20) {
                    Text(prompt)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 26)
                        )

                    TextEditor(text: $answer)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 220)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.4), lineWidth: 1)
                        }

                    Button {
                        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedAnswer.isEmpty else { return }
                        onPost(trimmedAnswer)
                        dismiss()
                    } label: {
                        Text("Post Blurb")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.black.opacity(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 0.82), in: Capsule())
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
                    Text("Comments on \(post.author)'s Blurb")
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
    @Binding var groups: [BlurbGroup]
    @Binding var selectedGroup: BlurbGroup
    @Binding var birthdayQuestionsEnabled: Bool
    @Binding var birthdayQuestion: String
    @Binding var birthdayTimestamp: Double
    @State private var showingJoinGroup = false

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

                        ForEach(groups) { group in
                            Button {
                                selectedGroup = group
                            } label: {
                                GroupCard(group: group, isSelected: group.id == selectedGroup.id)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showingJoinGroup = true
                        } label: {
                            Label("Join a group", systemImage: "person.badge.plus")
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
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView { name in
                    let newGroup = BlurbGroup(name: name, memberCount: 1)
                    groups.append(newGroup)
                    selectedGroup = newGroup
                }
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BIRTHDAY QUESTION")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)

            Toggle("Ask me a birthday question", isOn: $birthdayQuestionsEnabled)
                .font(.headline)

            if birthdayQuestionsEnabled {
                DatePicker("Your birthday", selection: birthdayDate, displayedComponents: .date)

                TextField("Optional birthday question", text: $birthdayQuestion, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                Text("If you leave this blank, Blurb asks its thoughtful default question on your birthday.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
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

    private var birthdayDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: birthdayTimestamp) },
            set: { birthdayTimestamp = $0.timeIntervalSince1970 }
        )
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

struct JoinGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    let onJoin: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.indigo)

                Text("Join a group")
                    .font(.title2.bold())

                Text("For now, use a group name. Firebase invite links and codes will replace this when we connect the backend.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                TextField("Group name", text: $groupName)
                    .textFieldStyle(.roundedBorder)

                Button("Join") {
                    let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    onJoin(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem {
                    Button("Cancel") { dismiss() }
                }
            }
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
    private let nextReportDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.date(byAdding: .month, value: 1, to: Date.now) ?? .now) ?? .now

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 76))
                                .foregroundStyle(.indigo.gradient)
                            Text("Sasin")
                                .font(.title.bold())
                            Text("College Roommates")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)

                        HStack(spacing: 12) {
                            StatCard(value: "3", label: "day streak", icon: "flame.fill", color: .orange)
                            StatCard(value: "12", label: "blurbs shared", icon: "text.bubble.fill", color: .indigo)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("BADGES")
                                .font(.caption.bold())
                                .tracking(1)
                                .foregroundStyle(.secondary)

                            BadgeRow(icon: "flame.fill", color: .orange, title: "On a roll", subtitle: "Answer 7 daily blurbs in a row")
                            BadgeRow(icon: "brain.head.profile", color: .purple, title: "Trivia ace", subtitle: "Get 5 weekly trivia answers right")
                            BadgeRow(icon: "person.3.fill", color: .blue, title: "Group regular", subtitle: "Share with a group 10 times")
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
