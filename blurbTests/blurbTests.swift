import Foundation
import Testing
@testable import blurb

struct blurbTests {
    private func post(_ date: Date, id: String, sample: Bool = false, streak: Bool = true,
                      prompt: DailyPrompt? = nil, answer: String = "Hello", edits: Int = 0) -> BlurbPost {
        BlurbPost(id: id, entryID: id, groupID: "group", authorID: "user", authorName: "Sasin",
                  authorPhotoURL: nil, imageURL: nil, answer: answer, prompt: prompt?.question ?? "Daily",
                  promptID: prompt?.id ?? id, pollOptions: [], isMonthlyReportPrompt: false,
                  createdAt: date, editedAt: nil, editCount: edits, countsTowardStreak: streak,
                  likeIDs: [], answerRank: 0, pointsAwarded: 0, commentCount: 0, isSample: sample)
    }

    @Test func samplesAndOtherMembersDoNotEarnRanks() {
        let sample = post(.now, id: "sample", sample: true)
        let progress = AchievementProgress.calculate(posts: [sample], userID: "user", groupID: "group")
        #expect(progress.allSatisfy { $0.value == 0 && $0.earned == nil })
        let other = AchievementProgress.calculate(posts: [post(.now, id: "real")], userID: "other", groupID: "group")
        #expect(other.allSatisfy { $0.value == 0 })
    }

    @Test func streakUsesPacificContentDaysAndKeepsHighestRank() {
        let formatter = ISO8601DateFormatter()
        // The first two entries straddle midnight, but precede the 5 AM reset.
        let dates = ["2026-09-18T06:00:00Z", "2026-09-18T11:00:00Z", "2026-09-18T13:00:00Z", "2026-09-19T13:00:00Z"]
        let posts = dates.enumerated().map { post(formatter.date(from: $0.element)!, id: "day-\($0.offset)") }
        let progress = AchievementProgress.calculate(posts: posts, userID: "user", groupID: "group")[0]
        #expect(progress.value == 3)
        #expect(progress.earned?.title == "On a Roll")
        #expect(progress.next?.title == "On Fire")
        let broken = AchievementProgress.calculate(posts: [posts[0], posts[3]], userID: "user", groupID: "group")[0]
        #expect(broken.value == 1)
    }

    @Test func triviaCountsDistinctCorrectUneditedPrompts() {
        let formatter = ISO8601DateFormatter()
        let dates = ["2026-09-03T20:00:00Z", "2026-09-10T20:00:00Z", "2026-09-17T20:00:00Z"]
        var posts = dates.enumerated().map { index, raw in
            let date = formatter.date(from: raw)!
            let trivia = QuestionBank.weeklyTrivia(for: date)
            return post(date, id: "trivia-\(index)", prompt: trivia, answer: trivia.acceptedAnswers[0])
        }
        posts.append(posts[0])
        let progress = AchievementProgress.calculate(posts: posts, userID: "user", groupID: "group")[1]
        #expect(progress.value == 3)
        #expect(progress.earned?.title == "Trivia Star")
        #expect(progress.next?.threshold == 5)
        let date = formatter.date(from: dates[0])!
        let trivia = QuestionBank.weeklyTrivia(for: date)
        let invalid = [post(date, id: "wrong", prompt: trivia, answer: "wrong"),
                       post(date, id: "edited", prompt: trivia, answer: trivia.acceptedAnswers[0], edits: 1)]
        #expect(AchievementProgress.calculate(posts: invalid, userID: "user", groupID: "group")[1].value == 0)
    }

    @Test func everyTierUnlocksAtItsThreshold() {
        let families = AchievementProgress.calculate(posts: [], userID: "user", groupID: "group")
        for family in families {
            for (index, tier) in family.tiers.enumerated() {
                let progress = AchievementProgress(id: family.id, value: tier.threshold, unit: family.unit, tiers: family.tiers)
                #expect(progress.earnedIndex == index)
                let before = AchievementProgress(id: family.id, value: tier.threshold - 1, unit: family.unit, tiers: family.tiers)
                #expect(before.next == tier)
            }
        }
    }

    @Test func objectionableLanguageFilterBlocksExactTermsAndThreatsWithoutSubstringFalsePositives() {
        #expect(ContentModeration.allows("That fire-retardant jacket worked."))
        #expect(ContentModeration.allows("We had a ridiculous, wonderful day."))
        #expect(!ContentModeration.allows("You should die"))
        #expect(!ContentModeration.allows("What a faggot"))
    }
}
