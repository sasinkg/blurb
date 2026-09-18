import SwiftUI

struct DemoMonthlyNewsletterView: View {
    let displayName: String
    let groupName: String

    private var reflections: [DemoReflection] {[
        DemoReflection(
            date: "AUGUST 5",
            question: "How did this month feel, in a few honest words?",
            responses: [
                DemoResponse(name: firstName, answer: "Full, surprising, and a little slower than I expected—in a good way."),
                DemoResponse(name: "Maya", answer: "Restorative. I finally made room for weekends that did not need an itinerary."),
                DemoResponse(name: "Alex", answer: "A little chaotic, but full of the kind of stories I know we will retell."),
                DemoResponse(name: "Jordan", answer: "Hopeful. A lot of small things started moving in the right direction.")
            ]
        ),
        DemoReflection(
            date: "AUGUST 12",
            question: "What was your favorite day this month, and why?",
            responses: [
                DemoResponse(name: firstName, answer: "The Saturday we got breakfast, walked by the water, and stayed out until sunset."),
                DemoResponse(name: "Maya", answer: "Dinner at Jordan’s. We planned to stay for an hour and somehow talked until midnight."),
                DemoResponse(name: "Alex", answer: "The beach day—even the part where we forgot the towels and had to improvise."),
                DemoResponse(name: "Jordan", answer: "My quiet Sunday morning with coffee, music, and nowhere I needed to be.")
            ]
        ),
        DemoReflection(
            date: "AUGUST 19",
            question: "When did you practice gratitude this month?",
            responses: [
                DemoResponse(name: firstName, answer: "On a difficult Tuesday, I wrote down three ordinary things that were still good."),
                DemoResponse(name: "Maya", answer: "Every time somebody in this group checked in without needing a reason."),
                DemoResponse(name: "Alex", answer: "Driving home after the concert, tired and happy, with everyone singing badly."),
                DemoResponse(name: "Jordan", answer: "When my mom called with good news and I remembered not to rush the conversation.")
            ]
        ),
        DemoReflection(
            date: "AUGUST 26",
            question: "What did this month teach you about yourself?",
            responses: [
                DemoResponse(name: firstName, answer: "I do not need a perfect plan before I begin."),
                DemoResponse(name: "Maya", answer: "Rest is more useful when I stop trying to earn it first."),
                DemoResponse(name: "Alex", answer: "I am better at asking for help than I used to be."),
                DemoResponse(name: "Jordan", answer: "Consistency can be quiet. It does not have to look impressive to count.")
            ]
        )
    ]}

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.93, blue: 0.82)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    masthead
                    opening
                    winnersSection
                    reflectionSection
                    photoSection
                    closing
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
        }
        .foregroundStyle(.black)
        .navigationTitle("Demo newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.96, green: 0.93, blue: 0.82), for: .navigationBar)
    }

    private var masthead: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DAILY BLURB")
                    .font(.system(size: 13, weight: .black))
                    .tracking(2.2)
                Spacer()
                Text("DEMO EDITION")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.78, blue: 0.02))
            }

            Rectangle()
                .frame(height: 3)

            HStack(alignment: .firstTextBaseline) {
                Text("THE MONTHLY")
                    .font(.system(size: 34, weight: .black, design: .serif))
                Spacer()
                Text("AUG 2026")
                    .font(.caption.bold())
                    .monospaced()
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A month worth remembering.")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            Text("A private collection of \(groupName)’s favorite moments, honest answers, and the little things that made August feel like August.")
                .font(.system(.body, design: .serif))
                .lineSpacing(5)

            HStack(spacing: 0) {
                newsletterStat("4", "PEOPLE")
                newsletterStat("16", "ANSWERS")
                newsletterStat("2", "PHOTOS")
            }
            .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
        }
        .padding(.bottom, 30)
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("FOUR QUESTIONS", subtitle: "THE MONTH IN WORDS")

            ForEach(Array(reflections.enumerated()), id: \.offset) { index, reflection in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(format: "%02d", index + 1))
                        Text("—")
                        Text(reflection.date)
                    }
                    .font(.caption.weight(.black))
                    .tracking(0.8)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    Text(reflection.question)
                        .font(.system(size: 23, weight: .bold, design: .serif))
                    VStack(spacing: 12) {
                        ForEach(reflection.responses) { response in
                            DemoGroupResponse(response: response)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 22)
                .overlay(alignment: .bottom) {
                    if index != reflections.count - 1 {
                        Rectangle().frame(height: 1)
                    }
                }
            }
        }
        .padding(.bottom, 30)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("EIGHT FRAMES", subtitle: "TWO FROM EACH PERSON")

            Text("Every member contributes one photo that includes themselves and one photo of the best food they had that month.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                ForEach(photoHighlights) { photo in
                    DemoPhotoPlaceholder(
                        number: photo.number,
                        icon: photo.icon,
                        caption: photo.caption,
                        contributor: photo.contributor
                    )
                }
            }
        }
        .padding(.bottom, 30)
    }

    private var winnersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("MONTHLY WINNERS", subtitle: "THE GROUP LEADERBOARD")

            DemoWinnerRow(
                icon: "checkmark.circle.fill",
                category: "MOST QUESTIONS ANSWERED",
                winner: "Maya",
                result: "28 answers"
            )
            DemoWinnerRow(
                icon: "star.fill",
                category: "MOST POINTS WON",
                winner: firstName,
                result: "46 points"
            )
            DemoWinnerRow(
                icon: "brain.head.profile",
                category: "TRIVIA CHAMPION",
                winner: "Jordan",
                result: "4 wins"
            )
        }
        .padding(16)
        .background(Color.white.opacity(0.42))
        .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
        .padding(.bottom, 30)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().frame(height: 3)
            Text("“A month looks different through everyone’s eyes.”")
                .font(.system(size: 29, weight: .bold, design: .serif))
                .italic()
            Text("END OF THE DEMO EDITION")
                .font(.caption2.weight(.black))
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
    }

    private func newsletterStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .serif))
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .tracking(1.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(red: 1, green: 0.78, blue: 0.02))
            Spacer()
            Text(subtitle)
                .font(.caption2.bold())
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? "Your"
    }

    private var photoHighlights: [DemoPhotoHighlight] {
        let people = [firstName, "Maya", "Alex", "Jordan"]
        let selfCaptions = [
            "Golden hour with the group",
            "A Saturday by the water",
            "Finally made it to the concert",
            "The quiet morning I needed"
        ]
        let foodCaptions = [
            "The pasta worth waiting for",
            "Perfect late-night tacos",
            "Breakfast that became lunch",
            "Homemade dumplings at last"
        ]

        return people.enumerated().flatMap { index, person in
            [
                DemoPhotoHighlight(
                    number: String(format: "%02d", index * 2 + 1),
                    icon: "person.crop.rectangle.fill",
                    caption: selfCaptions[index],
                    contributor: "\(person.uppercased()) · IN THE FRAME"
                ),
                DemoPhotoHighlight(
                    number: String(format: "%02d", index * 2 + 2),
                    icon: "fork.knife",
                    caption: foodCaptions[index],
                    contributor: "\(person.uppercased()) · BEST FOOD"
                )
            ]
        }
    }
}

private struct DemoReflection {
    let date: String
    let question: String
    let responses: [DemoResponse]
}

private struct DemoPhotoHighlight: Identifiable {
    let number: String
    let icon: String
    let caption: String
    let contributor: String
    var id: String { number }
}

private struct DemoResponse: Identifiable {
    let name: String
    let answer: String
    var id: String { name }
}

private struct DemoGroupResponse: View {
    let response: DemoResponse

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(String(response.name.prefix(1)).uppercased())
                .font(.caption.weight(.black))
                .frame(width: 30, height: 30)
                .background(Color(red: 1, green: 0.78, blue: 0.02), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(response.name.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                Text(response.answer)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DemoWinnerRow: View {
    let icon: String
    let category: String
    let winner: String
    let result: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .black))
                .frame(width: 38, height: 38)
                .foregroundStyle(.black)
                .background(Color(red: 1, green: 0.78, blue: 0.02))

            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(winner)
                    .font(.system(.headline, design: .serif).bold())
            }
            Spacer()
            Text(result)
                .font(.caption.bold())
                .monospacedDigit()
        }
    }
}

private struct DemoPhotoPlaceholder: View {
    let number: String
    let icon: String
    let caption: String
    let contributor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.74, blue: 0.12),
                        Color(red: 0.52, green: 0.31, blue: 0.76),
                        Color(red: 0.06, green: 0.10, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(number)
                    .font(.caption.weight(.black))
                    .monospaced()
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }

            Text(caption)
                .font(.system(.caption, design: .serif).bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(contributor)
                .font(.system(size: 8, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
