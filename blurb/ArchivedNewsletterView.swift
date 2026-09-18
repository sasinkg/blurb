import SwiftUI

struct ArchivedNewsletterView: View {
    let edition: NewsletterEdition
    let isInProgress: Bool

    init(edition: NewsletterEdition, isInProgress: Bool = false) {
        self.edition = edition
        self.isInProgress = isInProgress
    }

    private let paper = Color(red: 0.96, green: 0.93, blue: 0.82)
    private let accent = Color(red: 1, green: 0.78, blue: 0.02)

    private var writtenEntries: [NewsletterEntry] {
        edition.entries.filter { $0.imageURL == nil }
    }

    private var photoEntries: [NewsletterEntry] {
        edition.entries.filter { $0.imageURL != nil }
    }

    private var questions: [(id: String, prompt: String, date: Date, responses: [NewsletterEntry])] {
        let grouped = Dictionary(grouping: writtenEntries, by: \.promptID)
        return grouped.compactMap { key, responses in
            guard let first = responses.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return (key, first.prompt, first.createdAt, responses.sorted { $0.authorName < $1.authorName })
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    masthead
                    if isInProgress && edition.entries.isEmpty {
                        ContentUnavailableView(
                            "This month is just getting started",
                            systemImage: "newspaper",
                            description: Text("Monthly reflection answers and photo highlights will appear here as your group posts them.")
                        )
                        .foregroundStyle(.black)
                        .padding(.vertical, 36)
                    }
                    winners
                    answers
                    photos

                    Rectangle().frame(height: 3)
                    Text("A month looks different through everyone’s eyes.")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .italic()
                }
                .padding(18)
                .padding(.bottom, 30)
            }
        }
        .foregroundStyle(.black)
        .navigationTitle(edition.monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(paper, for: .navigationBar)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAILY BLURB")
                    .font(.caption.weight(.black))
                    .tracking(2)
                Spacer()
                Text(isInProgress ? "IN PROGRESS" : "SAVED EDITION")
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent)
            }
            Rectangle().frame(height: 3)
            Text(edition.monthLabel.uppercased())
                .font(.system(size: 38, weight: .black, design: .serif))
            Text("A private recap for \(edition.groupName).")
                .font(.system(.body, design: .serif))
        }
    }

    @ViewBuilder
    private var winners: some View {
        if edition.mostAnswersWinner != nil || edition.mostPointsWinner != nil {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("MONTHLY WINNERS")
                if let winner = edition.mostAnswersWinner {
                    winnerRow(icon: "checkmark.circle.fill", title: "MOST QUESTIONS ANSWERED", name: winner)
                }
                if let winner = edition.mostPointsWinner {
                    winnerRow(icon: "star.fill", title: "MOST POINTS WON", name: winner)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.42))
            .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
        }
    }

    @ViewBuilder
    private var answers: some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("THE MONTH IN WORDS")
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(String(format: "%02d", index + 1)) — \(question.date.formatted(.dateTime.month(.wide).day()))")
                            .font(.caption.weight(.black))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(question.prompt)
                            .font(.system(size: 23, weight: .bold, design: .serif))
                        ForEach(question.responses) { response in
                            HStack(alignment: .top, spacing: 11) {
                                Text(String(response.authorName.prefix(1)).uppercased())
                                    .font(.caption.weight(.black))
                                    .frame(width: 30, height: 30)
                                    .background(accent, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(response.authorName.uppercased())
                                        .font(.system(size: 10, weight: .black))
                                        .tracking(1)
                                    Text(response.answer)
                                        .font(.system(.body, design: .serif))
                                        .lineSpacing(4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .overlay(alignment: .bottom) { Rectangle().frame(height: 1) }
                }
            }
        }
    }

    @ViewBuilder
    private var photos: some View {
        if !photoEntries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("PHOTO HIGHLIGHTS")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(photoEntries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: URL(string: entry.imageURL ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color.black.opacity(0.08))
                                    .overlay { ProgressView() }
                            }
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)
                            .clipped()
                            .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
                            Text(entry.prompt)
                                .font(.system(.caption, design: .serif).bold())
                            Text(entry.authorName.uppercased())
                                .font(.system(size: 8, weight: .black))
                                .tracking(0.7)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .tracking(1.4)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accent)
    }

    private func winnerRow(icon: String, title: String, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 38, height: 38)
                .background(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(.headline, design: .serif).bold())
            }
        }
    }
}
