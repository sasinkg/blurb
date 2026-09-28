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

struct CroppedProfilePhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onComplete: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CroppedProfilePhotoPicker

        init(parent: CroppedProfilePhotoPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.86),
                  let prepared = preparedJPEG(from: data, maxDimension: 1_024) else {
                parent.isPresented = false
                return
            }
            parent.onComplete(prepared)
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
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
    @State private var showingTodayAnswers = false
    @State private var homeAnswerDraft: String?
    @State private var homeImageDraft: Data?
    @State private var homeInitialAnswer: String?
    @State private var dailyPromptClock = Date.now
    @State private var showingNewsletterQuestions = false
    @State private var showingBlurbMapAnnouncement = false
    @State private var showingNewsletterUpdate = false
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970
    @AppStorage("hasSeenBlurbMapAnnouncementV1") private var hasSeenBlurbMapAnnouncement = false
    @AppStorage("hasSeenNewsletterQuestionsUpdateV1") private var hasSeenNewsletterQuestionsUpdate = false

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
        .sheet(isPresented: $showingBlurbMapAnnouncement) {
            hasSeenBlurbMapAnnouncement = true
        } content: {
            BlurbMapAnnouncementView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingNewsletterUpdate, onDismiss: {
            hasSeenNewsletterQuestionsUpdate = true
        }) {
            NewsletterUpdateAnnouncementView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
        }
        .task(id: blurbStore.groupsLoaded) {
            guard blurbStore.groupsLoaded,
                  !blurbStore.groups.isEmpty,
                  !hasSeenNewsletterQuestionsUpdate else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            showingNewsletterUpdate = true
        }
        .task(id: blurbStore.groups.count) {
            guard blurbStore.groupsLoaded,
                  !blurbStore.groups.isEmpty,
                  !hasSeenBlurbMapAnnouncement,
                  hasSeenNewsletterQuestionsUpdate else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            showingBlurbMapAnnouncement = true
        }
        .alert("Daily Blurb", isPresented: Binding(
            get: { blurbStore.errorMessage != nil || blurbStore.listenerErrorMessage != nil || auth.errorMessage != nil },
            set: {
                if !$0 {
                    Task { @MainActor in
                        await Task.yield()
                        blurbStore.clearPresentedErrors()
                        auth.errorMessage = nil
                    }
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
                                Text(loaded
                                     ? "\(answered)/\(blurbStore.groups.count) groups answered today"
                                     : "Checking today's answers…")
                                .monospacedDigit()
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(height: 20, alignment: .leading)
                            }
                        }

                        if !newsletterPrompts.isEmpty {
                            Button { showingNewsletterQuestions = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "newspaper.fill")
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(newsletterPrompts.count == 1
                                             ? "HEY, YOU HAVE A MONTHLY QUESTION TO ANSWER"
                                             : "\(newsletterPrompts.count) MONTHLY QUESTIONS ARE READY")
                                            .font(.caption.weight(.black))
                                            .tracking(0.7)
                                        Text("Separate from today’s Daily Blurb · no points · editable through month-end")
                                            .font(.caption)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(.black)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 1, green: 0.78, blue: 0.02), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        HomePromptCard(
                            prompt: todayPrompt,
                            answeredAllGroups: hasAnsweredAllGroups,
                            answerStatusLoaded: !blurbStore.groups.isEmpty
                                && blurbStore.groups.allSatisfy { blurbStore.myAnswerStatusByGroup[$0.id] != nil }
                        ) {
                            if blurbStore.groups.isEmpty {
                                showingCreateGroup = true
                            } else if hasAnsweredAllGroups {
                                showingTodayAnswers = true
                            } else {
                                beginHomeAnswer()
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
                    initialAnswer: homeInitialAnswer,
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
                HomeAudiencePicker(
                    groups: blurbStore.groups,
                    answeredGroupIDs: Set(
                        blurbStore.myAnswerStatusByGroup.compactMap { $0.value ? $0.key : nil }
                    )
                ) { selectedGroups in
                    await applyHomeAnswer(to: selectedGroups)
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingNewsletterQuestions) {
                NewsletterQuestionsView(groups: blurbStore.groups, date: dailyPromptClock)
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingTodayAnswers) {
                TodayAnswersView(groups: blurbStore.groups, prompt: todayPrompt)
                    .presentationDetents([.medium, .large])
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

    private var newsletterPrompts: [DailyPrompt] {
        QuestionBank.releasedNewsletterPrompts(for: dailyPromptClock)
    }

    private var hasAnsweredAllGroups: Bool {
        !blurbStore.groups.isEmpty
            && blurbStore.groups.allSatisfy { blurbStore.myAnswerStatusByGroup[$0.id] == true }
    }

    private func offerHomeAudience() {
        guard homeAnswerDraft != nil || homeImageDraft != nil else {
            clearHomeDraft()
            return
        }
        guard blurbStore.groups.count == 1, let group = blurbStore.groups.first else {
            showingHomeAudience = true
            return
        }

        Task {
            _ = await applyHomeAnswer(to: [group])
        }
    }

    private func beginHomeAnswer() {
        homeInitialAnswer = nil
        guard blurbStore.groups.count == 1, let group = blurbStore.groups.first else {
            showingHomeAnswer = true
            return
        }

        Task {
            let existing = await blurbStore.existingAnswer(promptID: todayPrompt.id, in: group.id)
            homeInitialAnswer = existing?.answer
            showingHomeAnswer = true
        }
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
        homeInitialAnswer = nil
    }

}

private struct NewsletterAnswerTarget: Identifiable {
    let group: BlurbGroup
    let prompt: DailyPrompt
    let existingAnswer: BlurbPost?
    var id: String { "\(group.id)-\(prompt.id)" }
}

private struct NewsletterUpdateAnnouncementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Text("NEW IN BLURB")
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.black)
                            .background(Color(red: 1, green: 0.78, blue: 0.02))
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .frame(width: 38, height: 38)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Monthly newsletter questions")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text("A new way to save the stories that deserve more than one day.")
                            .foregroundStyle(.secondary)
                    }

                    updateRule(
                        icon: "calendar.badge.clock",
                        title: "Four questions each month",
                        text: "One arrives on each of the first four Fridays. Missed one? Catch up anytime through month-end."
                    )
                    updateRule(
                        icon: "plus.bubble.fill",
                        title: "Add a group question",
                        text: "Any member can add an optional extra prompt. It belongs only to that group and never replaces an official Friday question."
                    )
                    updateRule(
                        icon: "arrow.triangle.branch",
                        title: "Separate from your Daily Blurb",
                        text: "Newsletter answers do not complete the daily question and never earn points, placement medals, or streak credit."
                    )
                    updateRule(
                        icon: "pencil.and.outline",
                        title: "Edit and reuse freely",
                        text: "Edit an answer through month-end, reuse it in every unanswered group, or write something different for each group."
                    )
                    updateRule(
                        icon: "photo.badge.plus",
                        title: "Build the finished edition",
                        text: "Official and group-added answers join each member’s Photo of the Month and the group’s monthly highlights."
                    )

                    Text("Want to see these rules again? Open **Settings → How Questions Work**.")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(red: 1, green: 0.78, blue: 0.02).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

                    Button { dismiss() } label: {
                        Text("Got it")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 1, green: 0.78, blue: 0.02), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
            }
        }
    }

    private func updateRule(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.02))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .serif).bold())
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NewsletterQuestionRow: View {
    let number: Int
    let prompt: DailyPrompt
    let answered: Bool
    let action: () -> Void
    let reuseAction: (() -> Void)?
    var context: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                ZStack(alignment: .trailing) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(number))
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(Color(red: 1, green: 0.78, blue: 0.02), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(prompt.question)
                                .font(.system(.body, design: .serif).weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Text(answered ? "Answered · tap to edit" : "Tap to answer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(answered ? Color.green : Color.secondary)
                            if let context {
                                Text(context)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 34)
                    }

                    Image(systemName: answered ? "checkmark.circle.fill" : "square.and.pencil")
                        .foregroundStyle(answered ? Color.green : Color.secondary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let reuseAction {
                Divider()
                    .frame(height: 42)

                Button(action: reuseAction) {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.subheadline.weight(.bold))
                        Text("Reuse")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 54)
                    .background(
                        Color(red: 1, green: 0.78, blue: 0.02).opacity(0.9),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .padding(.trailing, 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reuse newsletter answer in another group")
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.22), lineWidth: 1)
        }
    }
}

struct NewsletterQuestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let groups: [BlurbGroup]
    let date: Date
    @State private var answerTarget: NewsletterAnswerTarget?
    @State private var reuseAnswer: String?
    @State private var reusePrompt: DailyPrompt?
    @State private var reuseSourceGroupID: String?
    @State private var showingReuseOptions = false
    @State private var reuseResultMessage = ""
    @State private var showingReuseResult = false
    @State private var newsletterAnswers: [String: BlurbPost] = [:]
    @State private var newsletterAnswersLoaded = false
    @State private var customQuestionsByGroup: [String: [GroupNewsletterQuestion]] = [:]
    @State private var addQuestionGroup: BlurbGroup?

    private var officialPrompts: [DailyPrompt] {
        QuestionBank.releasedNewsletterPrompts(for: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MONTHLY NEWSLETTER")
                                .font(.caption.weight(.black))
                                .tracking(1.4)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .foregroundStyle(.black)
                                .background(Color(red: 1, green: 0.78, blue: 0.02))
                            Text("Catch up anytime")
                                .font(.system(size: 30, weight: .bold, design: .serif))
                            Text("A new official question arrives each Friday. Groups can also add their own optional questions. Everything here is separate from your Daily Blurb, earns no points, and can be edited through the end of the month.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.name.uppercased())
                                        .font(.caption.weight(.black))
                                        .tracking(1)
                                    Spacer()
                                    Text(completionText(for: group))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(Array(officialPrompts.enumerated()), id: \.element.id) { index, prompt in
                                    let existing = newsletterAnswer(for: prompt, in: group)
                                    NewsletterQuestionRow(
                                        number: index + 1,
                                        prompt: prompt,
                                        answered: existing != nil,
                                        action: {
                                            answerTarget = NewsletterAnswerTarget(
                                                group: group,
                                                prompt: prompt,
                                                existingAnswer: existing
                                            )
                                        },
                                        reuseAction: reuseAction(
                                            for: existing,
                                            prompt: prompt,
                                            sourceGroupID: group.id
                                        )
                                    )
                                }

                                let customQuestions = customQuestionsByGroup[group.id] ?? []
                                if !customQuestions.isEmpty {
                                    Text("ADDED BY THIS GROUP")
                                        .font(.caption2.weight(.black))
                                        .tracking(0.8)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 5)

                                    ForEach(Array(customQuestions.enumerated()), id: \.element.id) { index, customQuestion in
                                        let prompt = customQuestion.prompt
                                        let existing = newsletterAnswer(for: prompt, in: group)
                                        NewsletterQuestionRow(
                                            number: officialPrompts.count + index + 1,
                                            prompt: prompt,
                                            answered: existing != nil,
                                            action: {
                                                answerTarget = NewsletterAnswerTarget(
                                                    group: group,
                                                    prompt: prompt,
                                                    existingAnswer: existing
                                                )
                                            },
                                            reuseAction: nil,
                                            context: "Added by \(customQuestion.authorName) · only in \(group.name)"
                                        )
                                    }
                                }

                                Button {
                                    addQuestionGroup = group
                                } label: {
                                    Label("Add a question to \(group.name)", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Newsletter questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $answerTarget, onDismiss: offerNewsletterReuse) { target in
                NewPostView(
                    prompt: target.prompt.question,
                    initialAnswer: target.existingAnswer?.answer,
                    themeSeed: target.group.name,
                    isNewsletterAnswer: true
                ) { answer, _ in
                    let succeeded: Bool
                    if let existing = target.existingAnswer {
                        succeeded = await blurbStore.editPost(existing, answer: answer)
                    } else {
                        succeeded = await blurbStore.createPost(
                            answer: answer,
                            prompt: target.prompt,
                            in: target.group.id
                        )
                    }
                    if succeeded {
                        await refreshNewsletterAnswer(for: target.prompt, in: target.group)
                        reuseAnswer = answer
                        reusePrompt = target.prompt
                        reuseSourceGroupID = target.group.id
                    }
                    return succeeded
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $addQuestionGroup) { group in
                AddNewsletterQuestionView(group: group, date: date) {
                    await loadCustomNewsletterQuestions(for: group)
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Reuse this newsletter answer?",
                isPresented: $showingReuseOptions,
                titleVisibility: .visible
            ) {
                if reusableGroups.count > 1 {
                    Button("All unanswered groups") {
                        reuseNewsletterAnswer(in: reusableGroups)
                    }
                }
                ForEach(reusableGroups) { group in
                    Button(group.name) {
                        reuseNewsletterAnswer(in: [group])
                    }
                }
                Button("Not now", role: .cancel) { clearReuseDraft() }
            } message: {
                Text("This adds the same answer to the group you choose. Your original answer stays where it is—there’s nothing to paste.")
            }
            .alert("Answer reused", isPresented: $showingReuseResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reuseResultMessage)
            }
            .task {
                await loadCustomNewsletterQuestions()
                await loadNewsletterAnswers()
            }
        }
    }

    private func completionText(for group: BlurbGroup) -> String {
        let groupPrompts = prompts(for: group)
        let answered = groupPrompts.filter { newsletterAnswer(for: $0, in: group) != nil }.count
        return "\(answered)/\(groupPrompts.count) answered"
    }

    private var reusableGroups: [BlurbGroup] {
        guard let prompt = reusePrompt else { return [] }
        return reusableGroups(for: prompt, excluding: reuseSourceGroupID)
    }

    private func reusableGroups(for prompt: DailyPrompt, excluding sourceGroupID: String?) -> [BlurbGroup] {
        guard newsletterAnswersLoaded,
              !prompt.id.hasPrefix("newsletter-custom-") else { return [] }
        return groups.filter {
            $0.id != sourceGroupID && newsletterAnswer(for: prompt, in: $0) == nil
        }
    }

    private func answerKey(promptID: String, groupID: String) -> String {
        "\(promptID)|\(groupID)"
    }

    private func newsletterAnswer(for prompt: DailyPrompt, in group: BlurbGroup) -> BlurbPost? {
        newsletterAnswers[answerKey(promptID: prompt.id, groupID: group.id)]
            ?? blurbStore.answer(for: prompt.id, in: group.id)
    }

    private func prompts(for group: BlurbGroup) -> [DailyPrompt] {
        officialPrompts + (customQuestionsByGroup[group.id] ?? []).map(\.prompt)
    }

    private func loadCustomNewsletterQuestions() async {
        for group in groups {
            guard !Task.isCancelled else { return }
            await loadCustomNewsletterQuestions(for: group)
        }
    }

    private func loadCustomNewsletterQuestions(for group: BlurbGroup) async {
        customQuestionsByGroup[group.id] = await blurbStore.loadCustomNewsletterQuestions(
            in: group.id,
            date: date
        )
    }

    private func loadNewsletterAnswers() async {
        var loaded: [String: BlurbPost] = [:]
        for group in groups {
            for prompt in prompts(for: group) {
                guard !Task.isCancelled else { return }
                if let answer = await blurbStore.existingAnswer(promptID: prompt.id, in: group.id) {
                    loaded[answerKey(promptID: prompt.id, groupID: group.id)] = answer
                }
            }
        }
        newsletterAnswers = loaded
        newsletterAnswersLoaded = true
    }

    private func refreshNewsletterAnswer(for prompt: DailyPrompt, in group: BlurbGroup) async {
        let key = answerKey(promptID: prompt.id, groupID: group.id)
        if let answer = await blurbStore.existingAnswer(promptID: prompt.id, in: group.id) {
            newsletterAnswers[key] = answer
        } else {
            newsletterAnswers[key] = nil
        }
    }

    private func reuseAction(
        for answer: BlurbPost?,
        prompt: DailyPrompt,
        sourceGroupID: String
    ) -> (() -> Void)? {
        guard let answer,
              !reusableGroups(for: prompt, excluding: sourceGroupID).isEmpty else { return nil }
        return {
            reuseAnswer = answer.answer
            reusePrompt = prompt
            reuseSourceGroupID = sourceGroupID
            showingReuseOptions = true
        }
    }

    private func offerNewsletterReuse() {
        guard reuseAnswer != nil, reusePrompt != nil, !reusableGroups.isEmpty else {
            clearReuseDraft()
            return
        }
        showingReuseOptions = true
    }

    private func reuseNewsletterAnswer(in destinations: [BlurbGroup]) {
        guard let answer = reuseAnswer, let prompt = reusePrompt else { return }
        Task {
            var completedGroups: [String] = []
            for group in destinations {
                if await blurbStore.existingAnswer(promptID: prompt.id, in: group.id) != nil {
                    await refreshNewsletterAnswer(for: prompt, in: group)
                    continue
                }
                guard await blurbStore.createPost(answer: answer, prompt: prompt, in: group.id) else {
                    clearReuseDraft()
                    return
                }
                await refreshNewsletterAnswer(for: prompt, in: group)
                completedGroups.append(group.name)
            }
            clearReuseDraft()
            if completedGroups.isEmpty {
                reuseResultMessage = "That question was already answered in the selected group."
            } else if completedGroups.count == 1 {
                reuseResultMessage = "Your answer is now in \(completedGroups[0])."
            } else {
                reuseResultMessage = "Your answer is now in \(completedGroups.count) more groups."
            }
            showingReuseResult = true
        }
    }

    private func clearReuseDraft() {
        reuseAnswer = nil
        reusePrompt = nil
        reuseSourceGroupID = nil
    }
}

private struct AddNewsletterQuestionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    let date: Date
    let onAdded: () async -> Void
    @State private var question = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GROUP QUESTION")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 1, green: 0.78, blue: 0.02))
                        Text("Ask \(group.name)")
                            .font(.system(size: 30, weight: .bold, design: .serif))
                        Text("This is an extra question for this group’s newsletter only. It won’t appear in another group, replace a Friday question, or award points.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField("What should the group answer?", text: $question, axis: .vertical)
                        .lineLimit(3...7)
                        .padding(15)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.primary.opacity(0.22), lineWidth: 1)
                        }

                    Text("\(question.count)/180")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(question.count > 180 ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Button {
                        addQuestion()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().tint(.black) }
                            Text(isSaving ? "Adding…" : "Add to newsletter")
                                .font(.headline)
                            Spacer()
                        }
                        .foregroundStyle(.black)
                        .padding(.vertical, 14)
                        .background(Color(red: 1, green: 0.78, blue: 0.02), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedQuestion.isEmpty || question.count > 180 || isSaving)
                    .opacity(trimmedQuestion.isEmpty || question.count > 180 ? 0.42 : 1)

                    Spacer()
                }
                .padding(22)
            }
            .navigationTitle("Add question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn’t add question", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    private func addQuestion() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if await blurbStore.addCustomNewsletterQuestion(trimmedQuestion, to: group.id, date: date) {
                await onAdded()
                dismiss()
            } else {
                saveError = blurbStore.errorMessage ?? "Please try again."
            }
            isSaving = false
        }
    }
}

private struct BlurbMapAnnouncementView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cityLocationEnabled") private var cityLocationEnabled = false
    @State private var isRequestingLocation = false
    @State private var locationError: String?

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Text("NEW IN BLURB")
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.black)
                            .background(Color(red: 1, green: 0.78, blue: 0.02))

                        Spacer()

                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .frame(width: 38, height: 38)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Introducing Blurb Map")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text("See the cities behind your group’s daily answers—and revisit everywhere you posted in the monthly newsletter.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.primary.opacity(0.055))
                        Image("WorldMapSilhouette")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .padding(16)
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.02))
                        mapDot("3", x: -78, y: -20)
                        mapDot("7", x: -42, y: 10)
                        mapDot("2", x: 58, y: -8)
                    }
                    .frame(height: 150)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Share your city on new Blurbs?", systemImage: "mappin.and.ellipse")
                            .font(.headline)
                        Text("Your phone converts your location to a city, region, and country. Your precise coordinates are never saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        enableCitySharing()
                    } label: {
                        HStack {
                            if isRequestingLocation {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text(isRequestingLocation ? "Finding your city…" : "Share my city")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 1, green: 0.78, blue: 0.02), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingLocation)

                    Button("Not now") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
                .padding(22)
            }
        }
        .alert("Location unavailable", isPresented: Binding(
            get: { locationError != nil },
            set: { if !$0 { locationError = nil } }
        )) {
            Button("OK", role: .cancel) { locationError = nil }
        } message: {
            Text(locationError ?? "Please try again.")
        }
    }

    private func mapDot(_ number: String, x: CGFloat, y: CGFloat) -> some View {
        Text(number)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.black, in: Circle())
            .offset(x: x, y: y)
    }

    private func enableCitySharing() {
        isRequestingLocation = true
        Task {
            if await CityLocationProvider.shared.currentCity() != nil {
                cityLocationEnabled = true
                dismiss()
            } else {
                cityLocationEnabled = false
                locationError = "Allow Location access for Daily Blurb in iPhone Settings to share your city. You can turn this off anytime in Blurb Settings."
            }
            isRequestingLocation = false
        }
    }
}

private struct HomeAudiencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let groups: [BlurbGroup]
    let answeredGroupIDs: Set<String>
    let apply: ([BlurbGroup]) async -> Bool
    @State private var selectedGroupIDs: Set<String>
    @State private var isApplying = false
    @State private var showingOverwriteWarning = false

    init(
        groups: [BlurbGroup],
        answeredGroupIDs: Set<String>,
        apply: @escaping ([BlurbGroup]) async -> Bool
    ) {
        self.groups = groups
        self.answeredGroupIDs = answeredGroupIDs
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
                        if selectedGroupIDs.isDisjoint(with: answeredGroupIDs) {
                            submit()
                        } else {
                            showingOverwriteWarning = true
                        }
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
    let answeredAllGroups: Bool
    let answerStatusLoaded: Bool
    let action: () -> Void

    private var accent: Color {
        Color(red: 1, green: 0.78, blue: 0.02)
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
                Group {
                    if answerStatusLoaded && answeredAllGroups {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("ANSWERED TODAY")
                                    .font(.caption.weight(.black))
                                    .tracking(0.8)
                                Text("View, edit, or delete your answers")
                                    .font(.caption2.weight(.semibold))
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(accent, in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        HStack {
                            Text(answerStatusLoaded ? "Tap to answer" : "Checking today's answers…")
                                .font(.caption.bold())
                            Spacer()
                            Image(systemName: answerStatusLoaded ? "square.and.pencil" : "ellipsis")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 44)
                .clipped()
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

private struct TodayAnswerTarget: Identifiable {
    let group: BlurbGroup
    let post: BlurbPost
    var id: String { post.id }
}

private struct TodayAnswersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blurbStore: BlurbStore
    let groups: [BlurbGroup]
    let prompt: DailyPrompt
    @State private var answersByGroup: [String: BlurbPost] = [:]
    @State private var answerOverrides: [String: String] = [:]
    @State private var isLoading = true
    @State private var editTarget: TodayAnswerTarget?
    @State private var deleteTarget: TodayAnswerTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                if isLoading {
                    ProgressView("Loading your answers…")
                } else if answersByGroup.isEmpty {
                    ContentUnavailableView(
                        "No answers yet",
                        systemImage: "square.and.pencil",
                        description: Text("Your answers will appear here after you post in a group.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TODAY’S QUESTION")
                                    .font(.caption.weight(.black))
                                    .tracking(1.1)
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color(red: 1, green: 0.78, blue: 0.02))
                                Text(prompt.question)
                                    .font(.system(size: 25, weight: .bold, design: .serif))
                            }

                            ForEach(groups) { group in
                                if let post = answersByGroup[group.id] {
                                    answerCard(post, in: group)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Today’s answers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: prompt.id) {
                await loadAnswers()
            }
            .sheet(item: $editTarget) { target in
                NewPostView(
                    prompt: target.post.prompt,
                    initialAnswer: answerOverrides[target.post.id] ?? target.post.answer,
                    themeSeed: target.group.name,
                    pollOptions: target.post.pollOptions
                ) { answer, _ in
                    let saved = await blurbStore.editPost(target.post, answer: answer)
                    if saved { answerOverrides[target.post.id] = answer }
                    return saved
                }
                .presentationBackground(.ultraThinMaterial)
            }
            .confirmationDialog(
                deleteTarget.map { "Delete your answer from \($0.group.name)?" } ?? "Delete this answer?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete answer", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    deleteTarget = nil
                    Task {
                        if await blurbStore.deletePost(target.post) {
                            answersByGroup[target.group.id] = nil
                            answerOverrides[target.post.id] = nil
                        }
                    }
                }
                Button("Keep answer", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Your answers in the other groups won’t be changed.")
            }
        }
    }

    private func answerCard(_ post: BlurbPost, in group: BlurbGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.name.uppercased())
                    .font(.caption.weight(.black))
                    .tracking(1)
                Spacer()
                if post.editedAt != nil {
                    Text("EDITED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if let imageURL = post.imageURL {
                BlurbAsyncImage(url: URL(string: imageURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(answerOverrides[post.id] ?? post.answer)
                .font(.system(.body, design: .serif).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    editTarget = TodayAnswerTarget(group: group, post: post)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteTarget = TodayAnswerTarget(group: group, post: post)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.22), lineWidth: 1)
        }
    }

    private func loadAnswers() async {
        var loaded: [String: BlurbPost] = [:]
        for group in groups {
            guard !Task.isCancelled else { return }
            if let answer = await blurbStore.existingAnswer(promptID: prompt.id, in: group.id) {
                loaded[group.id] = answer
            }
        }
        answersByGroup = loaded
        isLoading = false
    }
}

private struct HomeGroupCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var members: [GroupMemberProfile] = []
    @State private var avatarsExpanded = false

    private var accent: Color {
        Color(red: 1, green: 0.78, blue: 0.02)
    }

    private var ruleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : .black
    }

    private var displayedMembers: [GroupMemberProfile] {
        let loadedByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        var result = group.memberIDs.map { memberID in
            loadedByID[memberID] ?? GroupMemberProfile(
                id: memberID,
                name: "Group member",
                photoURL: nil
            )
        }
        if group.isExample {
            result += (0..<group.sampleParticipantCount).map { index in
                GroupMemberProfile(
                    id: "review-sample-\(index)",
                    name: "Example participant",
                    photoURL: nil
                )
            }
        }
        return result
    }

    var body: some View {
        let loadedCount = blurbStore.answerCountsByGroup[group.id]
        let displayedCount = (loadedCount ?? 0) + group.sampleParticipantCount
        let answeredMemberIDs = blurbStore.answeringMemberIDsByGroup[group.id] ?? []

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
                    let answerStatus = blurbStore.myAnswerStatusByGroup[group.id]
                    Image(systemName: answerStatus == true ? "checkmark" : "circle")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .opacity(answerStatus == nil ? 0 : 1)
                        .accessibilityHidden(answerStatus == nil)
                        .accessibilityLabel(answerStatus == true ? "You answered today" : "You have not answered today")
                }

                Divider()
                    .overlay(Color.primary.opacity(0.35))
                    .padding(.top, 7)
                    .padding(.bottom, 6)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ScrollView(.horizontal) {
                            HStack(spacing: avatarsExpanded ? 4 : -7) {
                                ForEach(displayedMembers) { member in
                                    let isSample = member.id.hasPrefix("review-sample-")
                                    HomeAnswerAvatar(
                                        member: member,
                                        answered: isSample || answeredMemberIDs.contains(member.id),
                                        accent: accent
                                    )
                                    .zIndex(isSample || answeredMemberIDs.contains(member.id) ? 1 : 0)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .animation(BlurbMotion.interactive, value: avatarsExpanded)
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                guard !avatarsExpanded else { return }
                                withAnimation(BlurbMotion.interactive) {
                                    avatarsExpanded = true
                                }
                            }
                        )
                        .task(id: avatarsExpanded) {
                            guard avatarsExpanded else { return }
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else { return }
                            withAnimation(BlurbMotion.interactive) {
                                avatarsExpanded = false
                            }
                        }

                        Text("answered today")
                            .font(.subheadline.weight(.medium))
                            .redacted(reason: loadedCount == nil ? .placeholder : [])
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(loadedCount == nil
                                        ? "Checking who answered today"
                                        : "\(displayedCount) of \(group.displayedParticipantCount) answered today")
                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .background(accent, in: Circle())
                        .foregroundStyle(.black)
                }
                .foregroundStyle(.primary)
            }
            .padding(17)
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(ruleColor, lineWidth: 2) }
        .task(id: "\(group.id)-\(group.memberIDs.count)") {
            members = await blurbStore.loadMemberProfiles(
                in: group.id,
                includeMonthlyProgress: false
            )
        }
    }
}

private struct HomeAnswerAvatar: View {
    let member: GroupMemberProfile
    let answered: Bool
    let accent: Color

    var body: some View {
        ProfilePhoto(urlString: member.photoURL, size: 30)
            .grayscale(answered ? 0 : 1)
            .opacity(answered ? 1 : 0.28)
            .overlay {
                Circle()
                    .stroke(answered ? accent : Color.secondary.opacity(0.35), lineWidth: answered ? 2.5 : 1)
            }
            .background(Color(uiColor: .systemBackground), in: Circle())
            .accessibilityLabel(member.name)
            .accessibilityValue(answered ? "Answered today" : "Has not answered today")
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
                .fill(Color(red: 1, green: 0.78, blue: 0.02))
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

private struct GroupMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var members: [GroupMemberProfile] = []
    @State private var isLoading = true
    @State private var nudgingMemberIDs: Set<String> = []
    @State private var nudgedMemberIDs: Set<String> = []
    @State private var nudgeAlertTitle = ""
    @State private var nudgeAlertMessage = ""
    @State private var showingNudgeAlert = false

    private var canManageGroup: Bool { auth.user?.uid == group.ownerID }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading members…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if members.isEmpty {
                    ContentUnavailableView(
                        "Members unavailable",
                        systemImage: "person.2.slash",
                        description: Text("Member profiles couldn't be loaded right now."))
                } else {
                    List(members) { member in
                        HStack(spacing: 10) {
                            ProfilePhoto(urlString: member.photoURL, size: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 7) {
                                    Text(member.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if member.id == group.ownerID {
                                        Text("OWNER")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 13) {
                                    monthlyProgressLabel(
                                        systemImage: "questionmark.circle",
                                        value: "\(member.newsletterAnsweredCount)/\(member.newsletterQuestionCount)",
                                        description: "monthly questions answered"
                                    )
                                    monthlyProgressLabel(
                                        systemImage: "photo",
                                        value: "\(member.hasPhotoOfMonth ? 1 : 0)/1",
                                        description: "Photo of the Month selected"
                                    )
                                }
                            }

                            Spacer(minLength: 4)

                            if canManageGroup,
                               member.id != auth.user?.uid,
                               !member.hasFinishedMonthlyProgress {
                                Button {
                                    sendNudge(to: member)
                                } label: {
                                    if nudgingMemberIDs.contains(member.id) {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: nudgedMemberIDs.contains(member.id) ? "checkmark" : "bell")
                                            .contentTransition(.symbolEffect(.replace))
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.circle)
                                .controlSize(.small)
                                .disabled(nudgingMemberIDs.contains(member.id) || nudgedMemberIDs.contains(member.id))
                                .animation(reduceMotion ? nil : BlurbMotion.quick, value: nudgedMemberIDs.contains(member.id))
                                .accessibilityLabel(nudgedMemberIDs.contains(member.id)
                                                    ? "Nudge sent to \(member.name)"
                                                    : "Nudge \(member.name)")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(group.memberCount) \(group.memberCount == 1 ? "Member" : "Members")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let loadedMembers = await blurbStore.loadMemberProfiles(in: group.id)
                // Replace the loading state atomically. Animating the entire list here
                // causes two full-screen render trees to overlap and creates ghosting.
                members = loadedMembers
                isLoading = false
            }
            .alert(nudgeAlertTitle, isPresented: $showingNudgeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(nudgeAlertMessage)
            }
        }
    }

    private func monthlyProgressLabel(systemImage: String, value: String, description: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(value) \(description)")
    }

    private func sendNudge(to member: GroupMemberProfile) {
        nudgingMemberIDs.insert(member.id)
        Task {
            let sent = await blurbStore.nudgeMonthlyProgress(for: member.id, in: group.id)
            nudgingMemberIDs.remove(member.id)
            if sent {
                nudgedMemberIDs.insert(member.id)
                nudgeAlertTitle = "Nudge sent"
                nudgeAlertMessage = "\(member.name) was reminded to finish their monthly check-in."
            } else {
                nudgeAlertTitle = "Couldn’t send nudge"
                nudgeAlertMessage = blurbStore.errorMessage ?? "Please try again in a moment."
            }
            showingNudgeAlert = true
        }
    }
}

private struct GroupFeedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var showingNewPost = false
    @State private var selectedPost: BlurbPost?
    @State private var postToEdit: BlurbPost?
    @State private var postToDelete: BlurbPost?
    @State private var answerToReuse: String?
    @State private var imageToReuse: Data?
    @State private var showingReuseOptions = false
    @State private var showingMembers = false
    @State private var dailyPromptClock = Date.now
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970
    @AppStorage("compactFeedEnabled") private var compactFeedEnabled = false
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingMembers = true } label: {
                    Image(systemName: "person.2.fill")
                }
                .accessibilityLabel("View members of \(group.name)")

                NavigationLink {
                    PhotoOfMonthPickerView(group: group)
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .overlay(alignment: .topTrailing) {
                            if blurbStore.photoOfMonthSelectionsLoaded
                                && blurbStore.photoOfMonthSelection(in: group.id) == nil {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                    .offset(x: 4, y: -3)
                            }
                        }
                }
                .accessibilityLabel("Choose Photo of the Month")

                NavigationLink {
                    GroupNewsletterHomeView(group: group)
                } label: {
                    Image(systemName: "newspaper.fill")
                }
                .accessibilityLabel("\(group.name) newsletter")
            }
        }
        .onAppear {
            blurbStore.select(group)
        }
        .sheet(isPresented: $showingMembers) {
            GroupMembersView(group: group)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
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
                            .background(Color(red: 1, green: 0.78, blue: 0.02))
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
                    withAnimation(reduceMotion ? nil : BlurbMotion.standard) {
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
                        compact: compactFeedEnabled,
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

private let moderationReportReasons = [
    "Harassment or bullying",
    "Hate speech",
    "Sexual content",
    "Violence or threats",
    "Spam",
    "Something else"
]

struct PostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var blurbStore: BlurbStore
    let post: BlurbPost
    let currentUserID: String?
    let compact: Bool
    let toggleLike: () -> Void
    let editAnswer: (() -> Void)?
    let deleteAnswer: (() -> Void)?
    let showComments: () -> Void
    @State private var showingPostEditor = false
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var moderationNotice: String?

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
        Group {
            if compact {
                compactCard
            } else {
                regularCard
            }
        }
        .onAppear { blurbStore.listenForComments(on: post) }
        .onDisappear { blurbStore.stopListeningForComments(on: post.id) }
        .sheet(isPresented: $showingPostEditor) {
            PostAnswerEditor(post: post)
        }
        .confirmationDialog("Why are you reporting this answer?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(moderationReportReasons, id: \.self) { reason in
                Button(reason) { reportPost(reason: reason) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your report is private and will be reviewed.")
        }
        .confirmationDialog("Block \(post.authorName)?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block user", role: .destructive) {
                Task {
                    if await blurbStore.blockUser(id: post.authorID, displayName: post.authorName) {
                        moderationNotice = "\(post.authorName) is blocked. Their answers and replies are now hidden."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their answers and replies will be hidden. You can unblock them in Settings.")
        }
        .alert("Moderation", isPresented: Binding(
            get: { moderationNotice != nil },
            set: { if !$0 { moderationNotice = nil } }
        )) {
            Button("OK", role: .cancel) { moderationNotice = nil }
        } message: {
            Text(moderationNotice ?? "")
        }
        .modifier(MemberProfileLinks(groupID: post.groupID))
    }

    private var regularCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                postHeader

            if post.isSample {
                Text("SAMPLE · \(ExampleGroupContent.question)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(mentionText(post.answer))
                .font(.body)
            if let city = post.cityLocation {
                Label(city.city, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Posted from \(city.city)")
            }

            if let imageURL = post.imageURL {
                BlurbAsyncImage(url: URL(string: imageURL)) { image in
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

            postReactions

            }
            .padding(14)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : .black, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.06), radius: 4, y: 2)
            .zIndex(1)

            if !previewComments.isEmpty { previewReplies }
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(memberNameText(post.authorName, userID: post.isSample ? nil : post.authorID))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                postMetadata

                Spacer(minLength: 4)
                postMenu
            }

            if post.isSample {
                Text("SAMPLE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(mentionText(post.answer))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let imageURL = post.imageURL {
                BlurbAsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            compactPostReactions
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.primary.opacity(0.18))
        }
    }

    private var compactPostReactions: some View {
        HStack(spacing: 20) {
            Button(action: toggleLike) {
                Label("\(post.likeCount)", systemImage: post.likeIDs.contains(currentUserID ?? "") ? "heart.fill" : "heart")
                    .foregroundStyle(post.likeIDs.contains(currentUserID ?? "") ? .red : .secondary)
                    .contentTransition(.numericText(value: Double(post.likeCount)))
            }
            .accessibilityLabel(post.likeIDs.contains(currentUserID ?? "") ? "Unlike answer" : "Like answer")
            .accessibilityValue("\(post.likeCount) likes")

            Button(action: showComments) {
                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .foregroundStyle(replyAccent)
                    .contentTransition(.numericText(value: Double(post.commentCount)))
            }
            .accessibilityLabel("Open replies")
            .accessibilityValue("\(post.commentCount) replies")

            Spacer(minLength: 0)
        }
        .font(.caption)
        .buttonStyle(.plain)
        .frame(minHeight: 30)
        .animation(reduceMotion ? nil : BlurbMotion.quick, value: post.likeCount)
        .animation(reduceMotion ? nil : BlurbMotion.quick, value: post.commentCount)
    }

    private var postHeader: some View {
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

            postMenu
        }
    }

    @ViewBuilder private var postMenu: some View {
        if editAnswer != nil || deleteAnswer != nil || (!post.isSample && post.authorID != currentUserID) {
            Menu {
                if editAnswer != nil {
                    Button("Edit answer") { showingPostEditor = true }
                }
                if let deleteAnswer {
                    Button("Delete answer", role: .destructive, action: deleteAnswer)
                }
                if !post.isSample && post.authorID != currentUserID {
                    Button("Report answer", systemImage: "exclamationmark.bubble") {
                        showingReportReasons = true
                    }
                    Button("Block \(post.authorName)", systemImage: "person.slash", role: .destructive) {
                        showingBlockConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
                    .contentShape(Rectangle())
            }
        } else {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
    }

    private var postReactions: some View {
        HStack(spacing: 18) {
                Button(action: toggleLike) {
                    HStack(spacing: 6) {
                        Image(systemName: post.likeIDs.contains(currentUserID ?? "") ? "heart.fill" : "heart")
                            .contentTransition(.symbolEffect(.replace))
                        Text("\(post.likeCount)")
                            .font(.caption.monospacedDigit())
                            .contentTransition(.numericText(value: Double(post.likeCount)))
                    }
                    .foregroundStyle(post.likeIDs.contains(currentUserID ?? "") ? .red : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(post.likeIDs.contains(currentUserID ?? "") ? "Unlike answer" : "Like answer")
                .accessibilityValue("\(post.likeCount) likes")
                .animation(reduceMotion ? nil : BlurbMotion.quick, value: post.likeCount)

                Button(action: showComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                        Text("\(post.commentCount)")
                            .font(.caption.monospacedDigit())
                            .contentTransition(.numericText(value: Double(post.commentCount)))
                    }
                    .foregroundStyle(replyAccent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Open replies")
                .accessibilityValue("\(post.commentCount) replies")
                .animation(reduceMotion ? nil : BlurbMotion.quick, value: post.commentCount)
                Spacer(minLength: 0)
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(.vertical, -6)
    }

    private var previewReplies: some View {
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

    private func reportPost(reason: String) {
        Task {
            if await blurbStore.reportPost(post, reason: reason) {
                moderationNotice = "Thanks. Your report was submitted for review."
            } else {
                moderationNotice = blurbStore.errorMessage ?? "The report could not be submitted."
            }
        }
    }

    private var postMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let rankColor {
                Image(systemName: "medal.fill")
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
        Color(red: 1, green: 0.78, blue: 0.02)
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
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
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
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        context.coordinator.scheduleHeightUpdate(for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        context.coordinator.scheduleHeightUpdate(for: textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var field: GrowingAnswerField
        private var heightUpdateScheduled = false

        init(field: GrowingAnswerField) {
            self.field = field
        }

        func textViewDidChange(_ textView: UITextView) {
            field.text = textView.text
            updateHeight(for: textView)
        }

        func scheduleHeightUpdate(for textView: UITextView) {
            guard !heightUpdateScheduled else { return }
            heightUpdateScheduled = true
            DispatchQueue.main.async {
                self.heightUpdateScheduled = false
                self.updateHeight(for: textView)
            }
        }

        func updateHeight(for textView: UITextView) {
            let width = max(textView.bounds.width, 1)
            let fittingHeight = textView.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
            let newHeight = min(max(fittingHeight, field.minimumHeight), field.maximumHeight)
            textView.isScrollEnabled = fittingHeight > field.maximumHeight

            guard abs(field.height - newHeight) > 0.5 else { return }
            field.height = newHeight
        }
    }
}

struct NewPostView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    let isNewsletterAnswer: Bool
    let onPost: (String, Data?) async -> Bool

    init(
        prompt: String,
        initialAnswer: String?,
        themeSeed: String,
        requiresPhoto: Bool = false,
        pollOptions: [String] = [],
        isNewsletterAnswer: Bool = false,
        onPost: @escaping (String, Data?) async -> Bool
    ) {
        self.prompt = prompt
        self.initialAnswer = initialAnswer
        self.themeSeed = themeSeed
        self.requiresPhoto = requiresPhoto
        self.pollOptions = pollOptions
        self.isNewsletterAnswer = isNewsletterAnswer
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
                            if initialAnswer == nil || isNewsletterAnswer {
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
                                            .contentTransition(.symbolEffect(.replace))
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
                                .animation(reduceMotion ? nil : BlurbMotion.quick, value: answer == option)
                            }

                            Button(initialAnswer == nil ? "Submit vote" : "Save vote") {
                                if initialAnswer == nil || isNewsletterAnswer {
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

                    Text(isNewsletterAnswer
                         ? "Newsletter answers earn no points or streak credit and stay editable through month-end."
                         : (initialAnswer == nil
                            ? "Once you post, your answer counts toward today’s streak."
                            : "You can edit once per day. Editing refreshes the timestamp, removes this answer from your streak, and may cost your first-place badge."))
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
                        if initialAnswer == nil || isNewsletterAnswer { submitAnswer() }
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
                        Text(isNewsletterAnswer
                             ? (initialAnswer == nil ? "Newsletter answer" : "Edit newsletter answer")
                             : (initialAnswer == nil ? "Answer today" : "Edit answer"))
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
        Color(red: 1, green: 0.78, blue: 0.02)
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

                        responseSummary
                        repliesList
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
                replyComposer
            }
            .onAppear { blurbStore.listenForComments(on: post) }
            .onDisappear { blurbStore.stopListeningForComments(on: post.id) }
        }
        .modifier(MemberProfileLinks(groupID: post.groupID))
    }

    private var responseSummary: some View {
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
                    if let city = post.cityLocation {
                        Label(city.city, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(mentionText(post.answer))
                .font(.system(.subheadline, design: .serif))
                .lineSpacing(2)
            if let imageURL = post.imageURL {
                BlurbAsyncImage(url: URL(string: imageURL)) { image in
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
    }

    private var repliesList: some View {
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

    private var replyComposer: some View {
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
    @EnvironmentObject private var blurbStore: BlurbStore
    @State private var editing = false
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var moderationNotice: String?
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
                    } else {
                        Menu {
                            Button("Report reply", systemImage: "exclamationmark.bubble") {
                                showingReportReasons = true
                            }
                            Button("Block \(comment.authorName)", systemImage: "person.slash", role: .destructive) {
                                showingBlockConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Reply options")
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
        .confirmationDialog("Why are you reporting this reply?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(moderationReportReasons, id: \.self) { reason in
                Button(reason) {
                    Task {
                        if await blurbStore.reportComment(comment, on: post, reason: reason) {
                            moderationNotice = "Thanks. Your report was submitted for review."
                        } else {
                            moderationNotice = blurbStore.errorMessage ?? "The report could not be submitted."
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your report is private and will be reviewed.")
        }
        .confirmationDialog("Block \(comment.authorName)?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block user", role: .destructive) {
                Task {
                    if await blurbStore.blockUser(id: comment.authorID, displayName: comment.authorName) {
                        moderationNotice = "\(comment.authorName) is blocked. Their answers and replies are now hidden."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their answers and replies will be hidden. You can unblock them in Settings.")
        }
        .alert("Moderation", isPresented: Binding(
            get: { moderationNotice != nil },
            set: { if !$0 { moderationNotice = nil } }
        )) {
            Button("OK", role: .cancel) { moderationNotice = nil }
        } message: {
            Text(moderationNotice ?? "")
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : BlurbMotion.interactive) {
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
        AsyncImage(url: URL(string: urlString ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.indigo.gradient)
                    .padding(size * 0.08)
            }
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
    @State private var showingPhotoCropper = false
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Button { showingPhotoCropper = true } label: {
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
                        .buttonStyle(.plain)
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
            .sheet(isPresented: $showingPhotoCropper) {
                CroppedProfilePhotoPicker(isPresented: $showingPhotoCropper) { croppedData in
                    photoData = croppedData
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't save profile", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
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
                .monospacedDigit()
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

private struct QuestionRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("How Blurb questions work")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text("Daily conversations and monthly newsletter questions run side by side. Answering one never completes the other.")
                            .foregroundStyle(.secondary)

                        rule(
                            icon: "sun.max.fill",
                            title: "Every day — Daily Blurb",
                            text: "One shared daily question appears at 5:00 AM Pacific. Answer it separately in each group to unlock that group’s conversation. Daily answers can earn placement points and streak credit."
                        )
                        rule(
                            icon: "brain.head.profile",
                            title: "Thursdays — Trivia",
                            text: "The first four Thursdays can use a trivia question as that day’s Daily Blurb. It follows the normal daily-answer rules."
                        )
                        rule(
                            icon: "newspaper.fill",
                            title: "Fridays — Newsletter question",
                            text: "One separate newsletter question unlocks on each of the first four Fridays. Released questions stay available through month-end. You can reuse one answer across groups or write a different answer for each group."
                        )
                        rule(
                            icon: "plus.bubble.fill",
                            title: "Optional group questions",
                            text: "Any member can add extra newsletter questions for one specific group. They appear after the official questions, stay inside that group, and cannot be reused in another group."
                        )
                        rule(
                            icon: "pencil.and.outline",
                            title: "Editing newsletter answers",
                            text: "Newsletter answers can be edited as often as needed through the end of the month. They never earn points, placement medals, or streak credit. Your Daily Blurb still needs its own answer."
                        )
                        rule(
                            icon: "photo.badge.plus",
                            title: "Photo of the Month",
                            text: "Choose one photo privately for each group. You can change it during the month; it is revealed when the finished newsletter is published."
                        )
                        rule(
                            icon: "sparkles.rectangle.stack.fill",
                            title: "What goes into the newsletter",
                            text: "The finished edition includes answers to the four Friday questions and any group-added questions, each member’s Photo of the Month, and monthly highlights such as participation, points, reactions, and cities."
                        )

                        Text("Friday notifications use your Daily Blurb reminder setting. Notifications must also be allowed in iPhone Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding()
                }
            }
            .navigationTitle("Question rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func rule(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Color(red: 1, green: 0.78, blue: 0.02), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .serif).bold())
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var blurbStore: BlurbStore
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("replyNotificationsEnabled") private var replyNotificationsEnabled = false
    @AppStorage("cityLocationEnabled") private var cityLocationEnabled = false
    @AppStorage("weeklyTriviaEnabled") private var weeklyTriviaEnabled = true
    @AppStorage("monthlyReportEnabled") private var monthlyReportEnabled = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @AppStorage("compactFeedEnabled") private var compactFeedEnabled = false
    @State private var groupToRename: BlurbGroup?
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var copiedGroupName: String?
    @State private var copiedItem = "Link"
    @State private var showingDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var reminderErrorMessage: String?
    @State private var currentCityName: String?
    @State private var showingQuestionRules = false
    @State private var isRefreshingCity = false

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

                            Divider()

                            Toggle("Compact group feed", isOn: $compactFeedEnabled)
                            Text("Show answers as simple, tweet-style rows with likes and comments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button { showingQuestionRules = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "questionmark.bubble.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.02))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("HOW QUESTIONS WORK")
                                        .font(.caption.weight(.black))
                                        .tracking(1)
                                    Text("Daily, trivia, newsletter, and monthly rules")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.primary.opacity(0.3), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)

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
                            Text("Get reminders at 10:00 AM and 7:00 PM, plus up to two nudges when friends post if you haven’t answered.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Weekly Trivia", isOn: $weeklyTriviaEnabled)
                            Toggle("Replies and @mentions", isOn: $replyNotificationsEnabled)
                                .onChange(of: replyNotificationsEnabled) { _, enabled in
                                    updateReplyNotifications(enabled: enabled)
                                }
                        }

                        settingsCard(title: "BLURB MAP") {
                            Toggle("Show my city on new Blurbs", isOn: $cityLocationEnabled)
                                .onChange(of: cityLocationEnabled) { _, enabled in
                                    updateCityLocation(enabled: enabled)
                                }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(currentCityName.map { "New Blurbs will show \($0)." } ?? "Optional and off by default. Daily Blurb converts your location to city, region, and country on your phone; precise coordinates are never saved.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                if cityLocationEnabled {
                                    Button {
                                        refreshCityLocation()
                                    } label: {
                                        if isRefreshingCity {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Label("Refresh", systemImage: "arrow.clockwise")
                                        }
                                    }
                                    .font(.caption.bold())
                                    .disabled(isRefreshingCity)
                                    .accessibilityLabel("Refresh current city")
                                }
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
                            NavigationLink {
                                MonthlyWrappedView(edition: MonthlyWrappedDemo.edition(
                                    groupName: blurbStore.selectedGroup?.name ?? "Roomies",
                                    displayName: blurbStore.profile.displayName
                                ))
                            } label: {
                                Label("Open demo Monthly Wrapped", systemImage: "sparkles.rectangle.stack.fill")
                                    .font(.subheadline.bold())
                            }
                        }

                        settingsCard(title: "PRIVACY") {
                            Label("Only members of a group can see its blurbs.", systemImage: "lock.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if !blurbStore.blockedUsers.isEmpty {
                                Divider()
                                Text("BLOCKED USERS")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(blurbStore.blockedUsers) { user in
                                    HStack {
                                        Label(user.displayName, systemImage: "person.slash")
                                        Spacer()
                                        Button("Unblock") {
                                            Task { await blurbStore.unblockUser(user) }
                                        }
                                        .font(.caption.bold())
                                    }
                                }
                            }
                        }

                        settingsCard(title: "SUPPORT") {
                            Link(destination: URL(string: "mailto:sasingudipati@gmail.com")!) {
                                Label("sasingudipati@gmail.com", systemImage: "envelope.fill")
                                    .font(.subheadline.bold())
                            }
                            Text("Contact support for help, safety concerns, or account questions.")
                                .font(.caption)
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
            .sheet(isPresented: $showingQuestionRules) {
                QuestionRulesView()
                    .presentationDetents([.large])
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
            .alert("Settings", isPresented: Binding(
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
            .task {
                guard cityLocationEnabled else { return }
                currentCityName = await CityLocationProvider.shared.currentCity()?.displayName
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

    private func updateCityLocation(enabled: Bool) {
        guard enabled else {
            currentCityName = nil
            return
        }
        Task {
            if let city = await CityLocationProvider.shared.currentCity() {
                currentCityName = city.displayName
            } else {
                cityLocationEnabled = false
                reminderErrorMessage = "City sharing needs Location access. Enable it in iPhone Settings, then try again."
            }
        }
    }

    private func refreshCityLocation() {
        guard !isRefreshingCity else { return }
        isRefreshingCity = true
        Task {
            if let city = await CityLocationProvider.shared.refreshCity() {
                currentCityName = city.displayName
            } else {
                reminderErrorMessage = "Your current city couldn’t be refreshed. Check Location access in iPhone Settings and try again."
            }
            isRefreshingCity = false
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 1, green: 0.78, blue: 0.02)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 3) {
            AnimatedBadgeIcon(systemName: tier.icon)
            Text(tier.title.uppercased())
                .tracking(0.5)
        }
        .font(.system(size: textSize, weight: .black, design: .serif))
        .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.02))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.title)
    }
}

private struct EarnedBadges: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: [AchievementProgress]
    @State private var expandedIndex: Int?
    @State private var collapseTask: Task<Void, Never>?

    private var earned: [AchievementTier] {
        progress.compactMap(\.earned)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(earned.enumerated()), id: \.offset) { index, tier in
                Button {
                    expandBadge(at: index)
                } label: {
                    if expandedIndex == index {
                        EarnedBadgeLabel(tier: tier)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        AnimatedBadgeIcon(systemName: tier.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.02))
                            .frame(width: 15, height: 18)
                            .accessibilityLabel(tier.title)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear { collapseTask?.cancel() }
    }

    private func expandBadge(at index: Int) {
        collapseTask?.cancel()
        withAnimation(reduceMotion ? nil : BlurbMotion.quick) {
            expandedIndex = index
        }
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : BlurbMotion.quick) {
                    expandedIndex = nil
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
                            BlurbAsyncImage(url: URL(string: member.photoURL ?? "")) { image in
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .contentTransition(.symbolEffect(.replace))
                Text("\(comment.likeIDs.count)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(comment.likeIDs.count)))
            }
            .font(.caption2)
            .foregroundStyle(liked ? .red : .secondary)
            .frame(minWidth: compact ? 32 : 44, minHeight: compact ? 22 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updating || auth.user == nil)
        .animation(reduceMotion ? nil : BlurbMotion.quick, value: liked)
        .animation(reduceMotion ? nil : BlurbMotion.quick, value: comment.likeIDs.count)
        .accessibilityLabel(liked ? "Unlike reply" : "Like reply")
        .accessibilityValue("\(comment.likeIDs.count) likes")
    }
}


private struct AnimatedBadgeIcon: View {
    let systemName: String
    var enabled = true

    var body: some View {
        Image(systemName: systemName)
            .opacity(enabled ? 1 : 0.42)
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
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var moderationNotice: String?
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
                } else {
                    Button("Report reply", systemImage: "exclamationmark.bubble") { showingReportReasons = true }
                    Button("Block \(comment.authorName)", systemImage: "person.slash", role: .destructive) {
                        showingBlockConfirmation = true
                    }
                }
            }
            .confirmationDialog("Delete your reply?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete reply", role: .destructive) {
                    Task { await blurbStore.deleteComment(comment, on: post) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Why are you reporting this reply?", isPresented: $showingReportReasons, titleVisibility: .visible) {
                ForEach(moderationReportReasons, id: \.self) { reason in
                    Button(reason) {
                        Task {
                            if await blurbStore.reportComment(comment, on: post, reason: reason) {
                                moderationNotice = "Thanks. Your report was submitted for review."
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Block \(comment.authorName)?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
                Button("Block user", role: .destructive) {
                    Task {
                        _ = await blurbStore.blockUser(id: comment.authorID, displayName: comment.authorName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their answers and replies will be hidden. You can unblock them in Settings.")
            }
            .alert("Moderation", isPresented: Binding(
                get: { moderationNotice != nil },
                set: { if !$0 { moderationNotice = nil } }
            )) {
                Button("OK", role: .cancel) { moderationNotice = nil }
            } message: {
                Text(moderationNotice ?? "")
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
