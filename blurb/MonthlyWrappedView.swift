import SwiftUI
import UniformTypeIdentifiers

struct MonthlyWrappedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var blurbStore: BlurbStore
    let edition: NewsletterEdition
    @State private var page = 0
    @State private var shareCard: WrappedShareImage?
    @State private var generatedPDF: WrappedPDF?
    @State private var pdfError: String?
    @State private var isExportingPDF = false
    @State private var showingPremium = false
    private let paper = Color(red: 0.96, green: 0.93, blue: 0.82)
    private var accent: Color {
        blurbStore.groups.first(where: { $0.id == edition.groupID })?.themeColor ?? GroupTheme.gold.color
    }

    private var currentGroup: BlurbGroup? {
        blurbStore.groups.first(where: { $0.id == edition.groupID })
    }

    private var slides: [WrappedSlide] {
        var result: [WrappedSlide] = [.intro, .stats, .locations(edition.stats.cities)]
        let answers = edition.entries.filter { $0.imageURL == nil && !$0.answer.isEmpty }
        let questions = Dictionary(grouping: answers, by: \.promptID).values
            .compactMap { responses -> (promptID: String, prompt: String, responses: [NewsletterEntry], createdAt: Date)? in
                guard let first = responses.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
                return (
                    first.promptID,
                    first.prompt,
                    responses.sorted { $0.authorName < $1.authorName },
                    first.createdAt
                )
            }
        let officialQuestions = questions
            .filter { !$0.promptID.hasPrefix("newsletter-custom-") }
            .sorted { $0.promptID.localizedStandardCompare($1.promptID) == .orderedAscending }
        let customQuestions = questions
            .filter { $0.promptID.hasPrefix("newsletter-custom-") }
            .sorted { $0.createdAt < $1.createdAt }
        result.append(contentsOf: officialQuestions.map { .question($0.prompt, $0.responses) })
        let photoGroups = Dictionary(grouping: edition.entries.filter { $0.imageURL != nil }, by: \.promptID)
            .values.sorted { ($0.first?.createdAt ?? .now) < ($1.first?.createdAt ?? .now) }
        result.append(contentsOf: photoGroups.compactMap { entries in
            guard let title = entries.first?.prompt else { return nil }
            return .photoGroup(title, entries.sorted { $0.authorName < $1.authorName })
        })
        result.append(contentsOf: customQuestions.map { .question($0.prompt, $0.responses) })
        result.append(contentsOf: [.awards, .final])
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                paper.ignoresSafeArea()
                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { index in
                        slide(slides[index])
                            .padding(24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 5) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule().fill(index <= page ? .black : .black.opacity(0.18)).frame(height: 4)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
                .animation(reduceMotion ? nil : BlurbMotion.quick, value: page)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    move(value.location.x < geometry.size.width / 2 ? -1 : 1)
                }
            )
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
        .sheet(item: $generatedPDF) { generatedPDF in
            WrappedPDFShareSheet(url: generatedPDF.url)
        }
        .sheet(isPresented: $showingPremium) {
            if let currentGroup {
                NavigationStack {
                    GroupPremiumHubView(group: currentGroup)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingPremium = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .alert("Couldn’t create PDF", isPresented: Binding(
            get: { pdfError != nil },
            set: { if !$0 { pdfError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfError ?? "Please try again.")
        }
        .task { renderShareCard() }
        .accessibilityAction(named: "Previous") { move(-1) }
        .accessibilityAction(named: "Next") { move(1) }
    }

    private func move(_ offset: Int) {
        let newPage = min(max(page + offset, 0), slides.count - 1)
        guard newPage != page else { return }
        if reduceMotion {
            page = newPage
        } else {
            withAnimation(BlurbMotion.page) { page = newPage }
        }
    }

    @MainActor private func renderShareCard() {
        let card = WrappedShareCard(edition: edition, accent: accent).frame(width: 1080, height: 1350)
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
            case let .photoGroup(title, entries):
                sectionLabel("PHOTO DESK")
                Text(title).font(.system(size: 28, weight: .black, design: .serif)).multilineTextAlignment(.center)
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { rowStart in
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(rowStart..<min(rowStart + 2, entries.count), id: \.self) { entryIndex in
                                    let entry = entries[entryIndex]
                                    VStack(alignment: .leading, spacing: 6) {
                                        if entry.imageURL?.hasPrefix("demo://") == true {
                                            DemoWrappedPhoto(url: entry.imageURL ?? "")
                                                .aspectRatio(4.0 / 5.0, contentMode: .fill).clipped()
                                                .overlay { Rectangle().stroke(.black, lineWidth: 2) }
                                        } else {
                                            BlurbAsyncImage(url: URL(string: entry.imageURL ?? "")) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                                                .aspectRatio(4.0 / 5.0, contentMode: .fit).clipped().overlay { Rectangle().stroke(.black, lineWidth: 2) }
                                        }
                                        if !entry.answer.isEmpty { Text(entry.answer).font(.system(.caption, design: .serif).bold()) }
                                        Text(entry.authorName.uppercased()).font(.system(size: 8, weight: .black)).tracking(0.8)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                if rowStart + 1 >= entries.count {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            case let .locations(cities):
                sectionLabel("BLURB MAP")
                Text("Where the group posted from").font(.system(size: 30, weight: .black, design: .serif)).multilineTextAlignment(.center)
                if cities.isEmpty {
                    Spacer()
                    Image(systemName: "map")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No locations were shared this month.")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                } else {
                    MonthlyCityMap(cities: cities, interactive: false, accent: accent)
                }
            case .awards:
                sectionLabel("MONTHLY HONORS")
                Text("The month’s standouts")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .multilineTextAlignment(.center)
                ScrollView {
                    VStack(spacing: 10) {
                        awardRow(
                            icon: "checkmark.circle.fill",
                            title: "MOST QUESTIONS ANSWERED",
                            name: edition.mostAnswersWinner,
                            detail: edition.mostAnswersWinner == nil ? "No answers this month" : nil
                        )
                        awardRow(
                            icon: "star.fill",
                            title: "MOST POINTS WON",
                            name: edition.mostPointsWinner,
                            detail: edition.mostPointsWinner == nil ? "No points awarded this month" : nil
                        )
                        awardRow(
                            icon: "heart.fill",
                            title: "MOST LIKED",
                            name: edition.stats.mostLiked?.authorName,
                            detail: highlightDetail(edition.stats.mostLiked, activity: "likes")
                        )
                        awardRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "MOST DISCUSSED",
                            name: edition.stats.mostCommented?.authorName,
                            detail: highlightDetail(edition.stats.mostCommented, activity: "replies")
                        )
                    }
                }
            case .final:
                WrappedNewspaperPage(
                    edition: edition,
                    accent: accent,
                    isExportingPDF: isExportingPDF,
                    isPremium: currentGroup?.isPremium == true,
                    exportPDF: exportPDF
                )
            }
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

    private func highlightDetail(_ item: WrappedHighlight?, activity: String) -> String? {
        guard let item, item.value > 0 else { return "No \(activity) this month" }
        return "\(item.value) \(activity) · “\(item.answer)”"
    }

    private func awardRow(icon: String, title: String, name: String?, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                Text((name ?? "—").uppercased())
                    .font(.system(.headline, design: .serif).weight(.black))
                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
    }

    private func exportPDF() {
        guard let currentGroup else { return }
        guard currentGroup.isPremium else {
            showingPremium = true
            return
        }
        guard !isExportingPDF else { return }
        isExportingPDF = true
        Task {
            defer { isExportingPDF = false }
            do {
                generatedPDF = WrappedPDF(url: try await NewsletterPDFExporter.makePDF(for: edition))
            } catch {
                pdfError = error.localizedDescription
            }
        }
    }
}

private struct DemoWrappedPhoto: View {
    let url: String
    var body: some View {
        if let image = croppedImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(Color.black.opacity(0.06))
        }
    }
    private var croppedImage: UIImage? {
        guard let source = UIImage(named: "DemoWrappedContactSheet")?.cgImage,
              let rawIndex = Int(url.split(separator: "/").last ?? "0") else { return nil }
        let index = url.contains("food") ? rawIndex + 4 : rawIndex
        let column = index % 4
        let row = index / 4
        let cellWidth = source.width / 4
        let cellHeight = source.height / 2
        guard let crop = source.cropping(to: CGRect(x: column * cellWidth, y: row * cellHeight, width: cellWidth, height: cellHeight)) else { return nil }
        return UIImage(cgImage: crop)
    }
}

private struct WrappedNewspaperPage: View {
    let edition: NewsletterEdition
    let accent: Color
    let isExportingPDF: Bool
    let isPremium: Bool
    let exportPDF: () -> Void
    private var questions: [(String, [NewsletterEntry])] {
        Dictionary(grouping: edition.entries.filter { $0.imageURL == nil && !$0.answer.isEmpty }, by: \.promptID)
            .values.compactMap { entries in entries.first.map { ($0.prompt, entries.sorted { $0.authorName < $1.authorName }) } }
    }
    private var photoGroups: [(String, [NewsletterEntry])] {
        Dictionary(grouping: edition.entries.filter { $0.imageURL != nil }, by: \.promptID)
            .values.compactMap { entries in entries.first.map { ($0.prompt, entries.sorted { $0.authorName < $1.authorName }) } }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("FINAL EDITION").font(.caption.weight(.black)).tracking(2).padding(7).background(accent)
                Text("THE \(edition.groupName.uppercased()) TIMES").font(.system(size: 31, weight: .black, design: .serif)).frame(maxWidth: .infinity)
                Rectangle().frame(height: 5)
                if edition.id == "demo-wrapped" {
                    Image("DemoWrappedContactSheet")
                        .resizable().scaledToFit()
                        .overlay { Rectangle().stroke(.black, lineWidth: 2) }
                    Text("THE MONTH IN PICTURES — FRIENDS, FOOD, AND THE MOMENTS BETWEEN")
                        .font(.system(size: 9, weight: .black)).tracking(0.8)
                }
                HStack {
                    newspaperStat(edition.stats.answerCount, "ANSWERS")
                    newspaperStat(edition.stats.questionCount, "QUESTIONS")
                    newspaperStat(edition.stats.photoCount, "PHOTOS")
                }
                if edition.mostAnswersWinner != nil || edition.mostPointsWinner != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("MONTHLY WINNERS").font(.caption.weight(.black)).tracking(1).padding(5).background(accent)
                        if let winner = edition.mostAnswersWinner { Text("Most answers — **\(winner)**") }
                        if let winner = edition.mostPointsWinner { Text("Points leader — **\(winner)**") }
                    }.font(.system(.caption, design: .serif)).padding(12).overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
                }
                if !edition.stats.cities.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THE MONTH ON THE MAP").font(.caption.weight(.black)).tracking(1).padding(5).background(accent)
                        MonthlyCityMap(cities: edition.stats.cities, interactive: false, accent: accent)
                    }
                }
                LazyVStack(spacing: 14) {
                    ForEach(Array(stride(from: 0, to: questions.count, by: 2)), id: \.self) { rowStart in
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(rowStart..<min(rowStart + 2, questions.count), id: \.self) { questionIndex in
                                let question = questions[questionIndex]
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(String(format: "%02d", questionIndex + 1)) · THE MONTH IN WORDS").font(.system(size: 7, weight: .black)).tracking(0.7).foregroundStyle(.secondary)
                                    Text(question.0).font(.system(size: 16, weight: .bold, design: .serif))
                                    ForEach(question.1) { entry in
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(entry.authorName.uppercased()).font(.system(size: 6, weight: .black)).tracking(0.5)
                                            Text(entry.answer).font(.system(size: 9, design: .serif)).lineLimit(5)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.trailing, 8)
                                .overlay(alignment: .trailing) { Rectangle().frame(width: 1) }
                            }
                            if rowStart + 1 >= questions.count {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                ForEach(Array(photoGroups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.0.uppercased()).font(.caption.weight(.black)).tracking(1).padding(5).background(accent)
                        LazyVStack(spacing: 12) {
                            ForEach(Array(stride(from: 0, to: group.1.count, by: 2)), id: \.self) { rowStart in
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(rowStart..<min(rowStart + 2, group.1.count), id: \.self) { entryIndex in
                                        let entry = group.1[entryIndex]
                                        VStack(alignment: .leading, spacing: 4) {
                                            if entry.imageURL?.hasPrefix("demo://") == true {
                                                DemoWrappedPhoto(url: entry.imageURL ?? "")
                                                    .aspectRatio(4.0 / 3.0, contentMode: .fill).clipped()
                                            } else {
                                                BlurbAsyncImage(url: URL(string: entry.imageURL ?? "")) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                                                    .aspectRatio(4.0 / 3.0, contentMode: .fit).clipped()
                                            }
                                            Text(entry.answer).font(.system(size: 9, weight: .bold, design: .serif))
                                            Text(entry.authorName.uppercased()).font(.system(size: 7, weight: .black))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                        .overlay { Rectangle().stroke(.black, lineWidth: 1) }
                                    }
                                    if rowStart + 1 >= group.1.count {
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle().frame(height: 4)
                Text("A month looks different through everyone’s eyes.").font(.system(.body, design: .serif)).italic().frame(maxWidth: .infinity)

                Button(action: exportPDF) {
                    HStack(spacing: 10) {
                        if isExportingPDF {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: isPremium ? "arrow.down.doc.fill" : "lock.fill")
                        }
                        Text(isExportingPDF ? "CREATING PDF…" : "EXPORT TO PDF")
                            .font(.caption.weight(.black))
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(accent)
                    .overlay { Rectangle().stroke(.black, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .disabled(isExportingPDF)
                .accessibilityHint(isPremium
                    ? "Creates and opens the newsletter PDF"
                    : "Opens Blurb Premium for this group")
            }.padding(.vertical, 6)
        }
    }
    private func newspaperStat(_ value: Int, _ label: String) -> some View {
        VStack { Text("\(value)").font(.title2.bold()); Text(label).font(.system(size: 7, weight: .black)) }
            .frame(maxWidth: .infinity).padding(8).overlay { Rectangle().stroke(.black) }
    }
}

private struct WrappedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

private struct WrappedPDFShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct WrappedShareCard: View {
    let edition: NewsletterEdition
    let accent: Color
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
            .frame(maxWidth: .infinity, alignment: .leading).padding(24).background(accent).overlay { Rectangle().stroke(.black, lineWidth: 3) }
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
    case intro, stats, locations([WrappedCityCount]), question(String, [NewsletterEntry]), photoGroup(String, [NewsletterEntry]), awards, final
}

enum MonthlyWrappedDemo {
    static func edition(groupName: String, displayName: String) -> NewsletterEdition {
        let name = displayName.split(separator: " ").first.map(String.init) ?? "You"
        let people = [name, "Maya", "Alex", "Jordan"]
        let questions: [(String, [String])] = [
            ("How did this month feel, in a few honest words?", ["Full, surprising, and a little slower than I expected—in a good way.", "Restorative. I finally made room for weekends that did not need an itinerary.", "A little chaotic, but full of the kind of stories I know we will retell.", "Hopeful. A lot of small things started moving in the right direction."]),
            ("What was your favorite day this month, and why?", ["The Saturday we got breakfast, walked by the water, and stayed out until sunset.", "Dinner at Jordan’s. We planned to stay for an hour and somehow talked until midnight.", "The beach day—even the part where we forgot the towels and had to improvise.", "My quiet Sunday morning with coffee, music, and nowhere I needed to be."]),
            ("When did you practice gratitude this month?", ["On a difficult Tuesday, I wrote down three ordinary things that were still good.", "Every time somebody in this group checked in without needing a reason.", "Driving home after the concert, tired and happy, with everyone singing badly.", "When my mom called with good news and I remembered not to rush the conversation."]),
            ("What did this month teach you about yourself?", ["I do not need a perfect plan before I begin.", "Rest is more useful when I stop trying to earn it first.", "I am better at asking for help than I used to be.", "Consistency can be quiet. It does not have to look impressive to count."])
        ]
        var entries = questions.enumerated().flatMap { questionIndex, item in
            people.enumerated().map { personIndex, person in
                NewsletterEntry(id: "demo-q\(questionIndex)-p\(personIndex)", authorName: person, answer: item.1[personIndex], prompt: item.0, promptID: "demo-question-\(questionIndex)", imageURL: nil, createdAt: .now.addingTimeInterval(-86400 * Double(26 - questionIndex * 7)))
            }
        }
        let selfCaptions = ["Golden hour with the group", "A Saturday by the water", "Finally made it to the concert", "The quiet morning I needed"]
        let foodCaptions = ["The pasta worth waiting for", "Perfect late-night tacos", "Breakfast that became lunch", "Homemade dumplings at last"]
        for (index, person) in people.enumerated() {
            entries.append(NewsletterEntry(id: "demo-photo-self-\(index)", authorName: person, answer: selfCaptions[index], prompt: "In the frame this month", promptID: "demo-photo-self", imageURL: "demo://self/\(index)", createdAt: .now))
            entries.append(NewsletterEntry(id: "demo-photo-food-\(index)", authorName: person, answer: foodCaptions[index], prompt: "Best food this month", promptID: "demo-photo-food", imageURL: "demo://food/\(index)", createdAt: .now))
        }
        return NewsletterEdition(
            id: "demo-wrapped", groupID: "demo", groupName: groupName,
            monthKey: "2026-08", monthLabel: "August 2026", entries: entries,
            mostAnswersWinner: "Maya", mostPointsWinner: name,
            stats: MonthlyWrappedStats(
                answerCount: 16, questionCount: 4, photoCount: 8,
                participatingMemberCount: 4, groupMemberCount: 4,
                mostLiked: WrappedHighlight(postID: entries[0].id, authorName: name, prompt: entries[0].prompt, answer: entries[0].answer, value: 18),
                mostCommented: WrappedHighlight(postID: entries[5].id, authorName: "Maya", prompt: entries[5].prompt, answer: entries[5].answer, value: 11),
                cities: [
                    WrappedCityCount(city: "Oakland", region: "CA", countryCode: "US", count: 7),
                    WrappedCityCount(city: "Seattle", region: "WA", countryCode: "US", count: 5),
                    WrappedCityCount(city: "Brooklyn", region: "NY", countryCode: "US", count: 4)
                ]
            )
        )
    }
}
