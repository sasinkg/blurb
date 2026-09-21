import Foundation

enum ExampleGroupContent {
    static let question = "What would you like to share with the group today?"

    static func prompt(for date: Date = .now) -> DailyPrompt {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let contentDate = calendar.date(byAdding: .hour, value: -5, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: contentDate)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return DailyPrompt(id: "review-example-\(day)", question: question, kind: .surface, isNewsletterFeature: true)
    }

    struct Sample {
        let id: String
        let name: String
        let prompt: String
        let answer: String
        let comment: String
    }

    static let posts = [
        Sample(id: "small-joy", name: "Maya", prompt: question,
               answer: "I took the long way home and found a tiny bookstore I'd never noticed. Left with a used novel and a new favorite spot.",
               comment: "This is a sample reply. Try adding your own comment below!"),
        Sample(id: "weekend", name: "Jordan", prompt: question,
               answer: "Pancakes, a walk by the water, and finally finishing our puzzle. Keeping the weekend simple for once.",
               comment: "A slow weekend sounds perfect. You can like this example answer too."),
        Sample(id: "reflection", name: "Sam", prompt: question,
               answer: "We cooked dinner together without a recipe. The pasta was questionable, but we laughed until the kitchen was clean.",
               comment: "Sample reflections also appear in this group's newsletter preview.")
    ]
}
