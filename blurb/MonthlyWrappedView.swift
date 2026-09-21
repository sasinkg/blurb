import SwiftUI

struct MonthlyWrappedView: View {
    let edition: NewsletterEdition
    @State private var page = 0

    private var slides: [WrappedSlide] {
        var result: [WrappedSlide] = [.intro]
        let stats = edition.stats
        if stats.answerCount > 0 { result.append(.stats) }
        if let item = stats.mostLiked, item.value > 0 { result.append(.highlight("Most liked", item, "heart.fill")) }
        if let item = stats.mostCommented, item.value > 0 { result.append(.highlight("Most discussed", item, "bubble.left.and.bubble.right.fill")) }
        let answers = edition.entries.filter { $0.imageURL == nil && !$0.answer.isEmpty }
        if let answer = answers.first { result.append(.answer(answer)) }
        for photo in edition.entries.filter({ $0.imageURL != nil }).prefix(6) { result.append(.photo(photo)) }
        result.append(.final)
        return result
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.18, green: 0.12, blue: 0.02)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            slide(slides[min(page, slides.count - 1)])
                .id(page)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .padding(24)
            HStack(spacing: 5) {
                ForEach(slides.indices, id: \.self) { index in
                    Capsule().fill(index <= page ? .white : .white.opacity(0.3)).frame(height: 3)
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
        .foregroundStyle(.white)
        .navigationTitle(edition.monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityAction(named: "Previous") { move(-1) }
        .accessibilityAction(named: "Next") { move(1) }
    }

    private func move(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { page = min(max(page + offset, 0), slides.count - 1) }
    }

    @ViewBuilder private func slide(_ slide: WrappedSlide) -> some View {
        VStack(spacing: 22) {
            Spacer()
            switch slide {
            case .intro:
                Image(systemName: "sparkles").font(.system(size: 58)).foregroundStyle(.yellow)
                Text(edition.monthLabel).font(.system(size: 48, weight: .black, design: .serif)).multilineTextAlignment(.center)
                Text("Monthly Wrapped for \(edition.groupName)").font(.title3).foregroundStyle(.white.opacity(0.75))
            case .stats:
                Text("The month in numbers").font(.largeTitle.bold())
                HStack { stat(edition.stats.answerCount, "answers"); stat(edition.stats.questionCount, "questions") }
                HStack { stat(edition.stats.photoCount, "photos"); stat(edition.stats.participatingMemberCount, "people") }
            case let .highlight(title, item, icon):
                Image(systemName: icon).font(.system(size: 50)).foregroundStyle(.yellow)
                Text(title).font(.largeTitle.bold())
                Text("“\(item.answer)”").font(.system(size: 30, weight: .semibold, design: .serif)).multilineTextAlignment(.center)
                Text("\(item.authorName) · \(item.value)").foregroundStyle(.secondary)
            case let .answer(entry):
                Text("A memorable answer").font(.headline).foregroundStyle(.yellow)
                Text(entry.prompt).font(.title2.bold()).multilineTextAlignment(.center)
                Text("“\(entry.answer)”").font(.system(size: 29, design: .serif)).multilineTextAlignment(.center)
                Text(entry.authorName.uppercased()).font(.caption.bold()).tracking(1)
            case let .photo(entry):
                AsyncImage(url: URL(string: entry.imageURL ?? "")) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text(entry.prompt).font(.title2.bold()).multilineTextAlignment(.center)
                Text(entry.authorName.uppercased()).font(.caption.bold()).tracking(1)
            case .final:
                Image(systemName: "heart.circle.fill").font(.system(size: 64)).foregroundStyle(.yellow)
                Text("That was \(edition.monthLabel)").font(.system(size: 42, weight: .black, design: .serif)).multilineTextAlignment(.center)
                Text("A month looks different through everyone’s eyes.").font(.title3).italic().multilineTextAlignment(.center)
            }
            Spacer()
            Text("Tap left or right to navigate").font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack { Text("\(value)").font(.system(size: 48, weight: .black)); Text(label.uppercased()).font(.caption.bold()) }
            .frame(maxWidth: .infinity).padding().background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }
}

private enum WrappedSlide {
    case intro, stats, highlight(String, WrappedHighlight, String), answer(NewsletterEntry), photo(NewsletterEntry), final
}
