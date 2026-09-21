import SwiftUI
import UniformTypeIdentifiers

struct MonthlyWrappedView: View {
    let edition: NewsletterEdition
    @State private var page = 0
    @State private var shareCard: WrappedShareImage?
    private let paper = Color(red: 0.96, green: 0.93, blue: 0.82)
    private let accent = Color(red: 1, green: 0.78, blue: 0.02)

    private var slides: [WrappedSlide] {
        var result: [WrappedSlide] = [.intro]
        let stats = edition.stats
        if stats.answerCount > 0 { result.append(.stats) }
        if let item = stats.mostLiked, item.value > 0 { result.append(.highlight("Most liked", item, "heart.fill")) }
        if let item = stats.mostCommented, item.value > 0 { result.append(.highlight("Most discussed", item, "bubble.left.and.bubble.right.fill")) }
        let answers = edition.entries.filter { !$0.answer.isEmpty }
        let questions = Dictionary(grouping: answers, by: \.promptID).values
            .compactMap { responses -> (NewsletterEntry, [NewsletterEntry])? in
                guard let first = responses.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
                return (first, responses.sorted { $0.authorName < $1.authorName })
            }
            .sorted { $0.0.createdAt < $1.0.createdAt }
        result.append(contentsOf: questions.map { .question($0.0.prompt, $0.1) })
        for photo in edition.entries.filter({ $0.imageURL != nil }) { result.append(.photo(photo)) }
        result.append(.final)
        return result
    }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            slide(slides[min(page, slides.count - 1)])
                .id(page)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .padding(24)
            HStack(spacing: 5) {
                ForEach(slides.indices, id: \.self) { index in
                    Capsule().fill(index <= page ? .black : .black.opacity(0.18)).frame(height: 4)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { move(-1) }
                Color.clear.contentShape(Rectangle()).onTapGesture { move(1) }
            }
        }
        .foregroundStyle(.black)
        .navigationTitle(edition.monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareCard {
                ShareLink(item: shareCard, preview: SharePreview("\(edition.monthLabel) Wrapped", image: Image(uiImage: shareCard.image))) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Monthly Wrapped")
            }
        }
        .task { renderShareCard() }
        .accessibilityAction(named: "Previous") { move(-1) }
        .accessibilityAction(named: "Next") { move(1) }
    }

    private func move(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { page = min(max(page + offset, 0), slides.count - 1) }
    }

    @MainActor private func renderShareCard() {
        let card = WrappedShareCard(edition: edition).frame(width: 1080, height: 1350)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        if let image = renderer.uiImage { shareCard = WrappedShareImage(image: image) }
    }

    @ViewBuilder private func slide(_ slide: WrappedSlide) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                HStack {
                    Text("DAILY BLURB").font(.caption.weight(.black)).tracking(2)
                    Spacer()
                    Text("MONTHLY WRAPPED").font(.caption2.weight(.black)).tracking(1).padding(.horizontal, 8).padding(.vertical, 5).background(accent)
                }
                Rectangle().frame(height: 3)
            }
            Spacer()
            switch slide {
            case .intro:
                Text("SPECIAL EDITION").font(.caption.weight(.black)).tracking(2).padding(8).background(accent)
                Text(edition.monthLabel.uppercased()).font(.system(size: 48, weight: .black, design: .serif)).multilineTextAlignment(.center)
                Rectangle().frame(height: 1)
                Text("The stories, people, and moments that defined \(edition.groupName)’s month.").font(.system(.title3, design: .serif)).multilineTextAlignment(.center)
            case .stats:
                sectionLabel("BY THE NUMBERS")
                Text("The month in numbers").font(.system(size: 38, weight: .black, design: .serif))
                HStack { stat(edition.stats.answerCount, "answers"); stat(edition.stats.questionCount, "questions") }
                HStack { stat(edition.stats.photoCount, "photos"); stat(edition.stats.participatingMemberCount, "people") }
            case let .highlight(title, item, icon):
                Image(systemName: icon).font(.system(size: 46)).foregroundStyle(.black).padding(14).background(accent)
                sectionLabel(title.uppercased())
                Text("“\(item.answer)”").font(.system(size: 30, weight: .semibold, design: .serif)).multilineTextAlignment(.center)
                Text("BY \(item.authorName.uppercased()) · \(item.value)").font(.caption.weight(.black)).tracking(1)
            case let .question(prompt, responses):
                sectionLabel("THE MONTH IN WORDS")
                Text(prompt).font(.system(size: 27, weight: .bold, design: .serif)).multilineTextAlignment(.center)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(responses) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.authorName.uppercased()).font(.caption.weight(.black)).tracking(1)
                                Text(entry.answer).font(.system(.body, design: .serif)).lineSpacing(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                            .overlay(alignment: .bottom) { Rectangle().frame(height: 1) }
                        }
                    }
                }
            case let .photo(entry):
                AsyncImage(url: URL(string: entry.imageURL ?? "")) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .overlay { Rectangle().stroke(.black, lineWidth: 3) }
                Text(entry.prompt).font(.title2.bold()).multilineTextAlignment(.center)
                Text(entry.authorName.uppercased()).font(.caption.bold()).tracking(1)
            case .final:
                Text("FINAL EDITION").font(.caption.weight(.black)).tracking(2).padding(8).background(accent)
                Text("That was \(edition.monthLabel)").font(.system(size: 42, weight: .black, design: .serif)).multilineTextAlignment(.center)
                Text("A month looks different through everyone’s eyes.").font(.title3).italic().multilineTextAlignment(.center)
            }
            Spacer()
            Rectangle().frame(height: 1)
            Text("TAP LEFT OR RIGHT TO NAVIGATE").font(.system(size: 9, weight: .black)).tracking(1).foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.black)).tracking(1.4).padding(.horizontal, 9).padding(.vertical, 6).background(accent)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack { Text("\(value)").font(.system(size: 48, weight: .black)); Text(label.uppercased()).font(.caption.bold()) }
            .frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.38)).overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
    }
}

private struct WrappedShareCard: View {
    let edition: NewsletterEdition
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.93, blue: 0.82)
            VStack(alignment: .leading, spacing: 46) {
                HStack { Text("DAILY BLURB").tracking(6); Spacer(); Text("MONTHLY WRAPPED") }
                    .font(.system(size: 28, weight: .black))
                Rectangle().frame(height: 6)
                Spacer()
                Text(edition.monthLabel.uppercased()).font(.system(size: 86, weight: .black, design: .serif))
                Text("\(edition.groupName)’s stories, people, and moments.").font(.system(size: 40, weight: .semibold, design: .serif))
                HStack(spacing: 24) {
                    shareStat(edition.stats.answerCount, "ANSWERS")
                    shareStat(edition.stats.questionCount, "QUESTIONS")
                    shareStat(edition.stats.photoCount, "PHOTOS")
                }
                Spacer()
                Text("A month looks different through everyone’s eyes.").font(.system(size: 30, design: .serif)).italic()
            }.padding(76)
        }.foregroundStyle(.black)
    }
    private func shareStat(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text("\(value)").font(.system(size: 64, weight: .black)); Text(title).font(.system(size: 20, weight: .bold)).tracking(2) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Color(red: 1, green: 0.78, blue: 0.02)).overlay { Rectangle().stroke(.black, lineWidth: 3) }
    }
}

private struct WrappedShareImage: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = item.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
    }
}

private enum WrappedSlide {
    case intro, stats, highlight(String, WrappedHighlight, String), question(String, [NewsletterEntry]), photo(NewsletterEntry), final
}

enum MonthlyWrappedDemo {
    static func edition(groupName: String, displayName: String) -> NewsletterEdition {
        let name = displayName.split(separator: " ").first.map(String.init) ?? "You"
        let entries = [
            NewsletterEntry(id: "demo-1", authorName: name, answer: "The night we made dinner without a recipe and somehow stayed at the table for three hours.", prompt: "What moment do you want to remember?", promptID: "demo-memory", imageURL: nil, createdAt: .now.addingTimeInterval(-86400 * 12)),
            NewsletterEntry(id: "demo-2", authorName: "Maya", answer: "Everyone showing up when I needed them, without making me ask twice.", prompt: "What made you feel cared for this month?", promptID: "demo-care", imageURL: nil, createdAt: .now.addingTimeInterval(-86400 * 6))
        ]
        return NewsletterEdition(
            id: "demo-wrapped", groupID: "demo", groupName: groupName,
            monthKey: "2026-08", monthLabel: "August 2026", entries: entries,
            mostAnswersWinner: "Maya", mostPointsWinner: name,
            stats: MonthlyWrappedStats(
                answerCount: 74, questionCount: 24, photoCount: 12,
                participatingMemberCount: 4, groupMemberCount: 4,
                mostLiked: WrappedHighlight(postID: "demo-1", authorName: name, prompt: entries[0].prompt, answer: entries[0].answer, value: 18),
                mostCommented: WrappedHighlight(postID: "demo-2", authorName: "Maya", prompt: entries[1].prompt, answer: entries[1].answer, value: 11)
            )
        )
    }
}
