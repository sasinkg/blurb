import Foundation

enum ContentModeration {
    static let rejectionMessage = "That text contains language that isn’t allowed. Please revise it."

    // This is intentionally a small, high-confidence first line of defense. Reports
    // remain available for harassment or harmful context a word list cannot detect.
    private static let blockedWords: Set<String> = [
        "cunt", "faggot", "fag", "nigger", "nigga", "retard", "retarded",
        "whore", "slut"
    ]

    private static let blockedPhrases = [
        "kill yourself", "go kill yourself", "you should die"
    ]

    static func allows(_ text: String) -> Bool {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard blockedWords.isDisjoint(with: Set(words)) else { return false }
        let collapsed = words.joined(separator: " ")
        return !blockedPhrases.contains { collapsed.contains($0) }
    }
}
