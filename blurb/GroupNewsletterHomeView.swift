import SwiftUI

struct GroupNewsletterHomeView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    let group: BlurbGroup
    @State private var promptClock = Date.now
    @AppStorage("birthdayQuestionsEnabled") private var birthdayQuestionsEnabled = false
    @AppStorage("birthdayQuestion") private var birthdayQuestion = ""
    @AppStorage("birthdayTimestamp") private var birthdayTimestamp = Date.now.timeIntervalSince1970

    private var todayPromptID: String {
        if blurbStore.canAddReviewExamples {
            return ExampleGroupContent.prompt(for: promptClock).id
        }
        return QuestionBank.prompt(
            for: promptClock,
            birthdayPrompt: birthdayQuestion,
            birthday: birthdayQuestionsEnabled ? Date(timeIntervalSince1970: birthdayTimestamp) : nil
        ).id
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private var currentPosts: [BlurbPost] {
        blurbStore.posts.filter {
            $0.groupID == group.id
                && calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .month)
                && blurbStore.hasAnswered(promptID: $0.isSample ? todayPromptID : $0.promptID, in: group.id)
        }
    }

    private var currentEdition: NewsletterEdition {
        let entries = currentPosts
            .filter { $0.isMonthlyReportPrompt || $0.imageURL != nil }
            .map {
                NewsletterEntry(
                    id: $0.id,
                    authorName: $0.authorName,
                    answer: $0.answer,
                    prompt: $0.isSample ? ExampleGroupContent.question : $0.prompt,
                    promptID: $0.isSample ? "review-example-samples" : $0.promptID,
                    imageURL: $0.imageURL,
                    createdAt: $0.createdAt
                )
            }
        let counts = Dictionary(grouping: currentPosts, by: \.authorName).mapValues(\.count)
        let points = Dictionary(grouping: currentPosts, by: \.authorName)
            .mapValues { $0.reduce(0) { $0 + $1.pointsAwarded } }
        let components = calendar.dateComponents([.year, .month], from: .now)
        let monthKey = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        return NewsletterEdition(
            id: "current-\(group.id)-\(monthKey)",
            groupID: group.id,
            groupName: group.name,
            monthKey: monthKey,
            monthLabel: Date.now.formatted(.dateTime.month(.wide).year()),
            entries: entries,
            mostAnswersWinner: counts.max(by: { $0.value < $1.value })?.key,
            mostPointsWinner: points.max(by: { $0.value < $1.value })?.key
        )
    }

    private var archivedEditions: [NewsletterEdition] {
        blurbStore.newsletterEditions.filter { $0.groupID == group.id }
    }

    private var generationDate: Date {
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: .now) ?? .now
        var components = calendar.dateComponents([.year, .month], from: nextMonth)
        components.day = 3
        return calendar.date(from: components) ?? nextMonth
    }

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(group.name)
                        .font(.system(size: 38, weight: .bold, design: .serif))
                    Text("Monthly newsletter")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("\(currentEdition.monthLabel) hasn’t been generated yet. The finished edition will be saved on \(generationDate.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    NavigationLink {
                        PhotoOfMonthPickerView(group: group)
                    } label: {
                        newsletterCard(
                            title: "Photo of the Month",
                            subtitle: blurbStore.photoOfMonthSelection(in: group.id) == nil
                                ? "Choose one of your photos privately"
                                : "Selected — you can change it until month end",
                            icon: blurbStore.photoOfMonthSelection(in: group.id) == nil ? "photo.badge.plus" : "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    newsletterCard(
                        title: currentEdition.monthLabel,
                        subtitle: "Locked until the finished edition is generated",
                        icon: "lock.fill"
                    )
                    .accessibilityLabel("\(currentEdition.monthLabel) newsletter locked. Not generated yet.")

                    NavigationLink {
                        GroupNewsletterArchiveView(group: group, editions: archivedEditions)
                    } label: {
                        newsletterCard(
                            title: "Previous editions",
                            subtitle: archivedEditions.isEmpty ? "Your first saved edition will appear next month" : "\(archivedEditions.count) saved",
                            icon: "archivebox.fill"
                        )
                    }
                    .buttonStyle(.plain)

                }
                .padding()
            }
        }
        .task {
            while !Task.isCancelled {
                promptClock = .now
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func newsletterCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(Color(red: 1, green: 0.78, blue: 0.02))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .serif).bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.45), lineWidth: 1.5) }
    }
}

private struct PhotoOfMonthPickerView: View {
    @EnvironmentObject private var blurbStore: BlurbStore
    @Environment(\.dismiss) private var dismiss
    let group: BlurbGroup
    @State private var savingPostID: String?

    private var posts: [BlurbPost] { blurbStore.photoPostsForCurrentMonth(in: group.id) }
    private var selection: PhotoOfMonthSelection? { blurbStore.photoOfMonthSelection(in: group.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick one photo you posted this month. Your choice stays private until the monthly recap, and you can change it until the month ends.")
                    .foregroundStyle(.secondary)
                if posts.isEmpty {
                    ContentUnavailableView("No photos yet", systemImage: "photo", description: Text("Post a photo in this group, then return here to select it."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                        ForEach(posts) { post in
                            Button {
                                savingPostID = post.id
                                Task {
                                    if await blurbStore.selectPhotoOfMonth(post) { dismiss() }
                                    savingPostID = nil
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: URL(string: post.imageURL ?? "")) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: { Rectangle().fill(.quaternary) }
                                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                                    if selection?.postID == post.id {
                                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.white, .green).padding(8)
                                    }
                                    if savingPostID == post.id { ProgressView().padding(10) }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(savingPostID != nil)
                            .accessibilityLabel(selection?.postID == post.id ? "Selected photo" : "Select photo")
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("Photo of the Month")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GroupNewsletterArchiveView: View {
    let group: BlurbGroup
    let editions: [NewsletterEdition]

    var body: some View {
        List {
            if editions.isEmpty {
                ContentUnavailableView(
                    "No previous editions yet",
                    systemImage: "archivebox",
                    description: Text("\(group.name)’s first newsletter will be saved after this month ends.")
                )
            } else {
                ForEach(editions) { edition in
                    NavigationLink {
                        ArchivedNewsletterView(edition: edition)
                    } label: {
                        Label(edition.monthLabel, systemImage: "newspaper.fill")
                    }
                }
            }
        }
        .navigationTitle("Newsletter archive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
