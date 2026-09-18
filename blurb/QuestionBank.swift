import Foundation

enum PromptKind: String, Codable {
    case surface = "Everyday"
    case featured = "Newsletter"
    case timely = "This month"
    case trivia = "Weekly trivia"
    case birthday = "Birthday"
}

struct DailyPrompt: Identifiable, Hashable {
    let id: String
    let question: String
    let kind: PromptKind
    let isNewsletterFeature: Bool
    let acceptedAnswers: [String]
    let pollOptions: [String]

    init(id: String, question: String, kind: PromptKind, isNewsletterFeature: Bool, acceptedAnswers: [String] = [], pollOptions: [String] = []) {
        self.id = id
        self.question = question
        self.kind = kind
        self.isNewsletterFeature = isNewsletterFeature
        self.acceptedAnswers = acceptedAnswers
        self.pollOptions = pollOptions
    }

    var requiresPhoto: Bool { id.contains("hidden-report-photo") }
    var isTrivia: Bool { kind == .trivia }
    var isPoll: Bool { !pollOptions.isEmpty }
    var allowsEditing: Bool { !isTrivia }

    func isCorrect(_ answer: String) -> Bool {
        guard isTrivia else { return true }
        let normalized = Self.normalize(answer)
        return acceptedAnswers.contains { Self.normalize($0) == normalized }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum QuestionBank {
    private static var pacificCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// Treat midnight through 4:59 AM Pacific as part of the prior content day.
    private static func contentDate(for date: Date) -> Date {
        pacificCalendar.date(byAdding: .hour, value: -5, to: date) ?? date
    }

    private static let weeklyReflectionPrompts = [
        "What is one moment from this week you want to remember?",
        "Post a picture of yourself from this month.",
        "What felt most meaningful to you this week?",
        "Post a picture of the best meal you ate this month.",
        "What are you carrying forward from this week?"
    ]
    // Each month has 20 easy prompts, 4 newsletter candidates, and 5 timely prompts.
    // The 17 bonus prompts below make the complete local bank exactly 365 prompts.
    private static let surfaceTemplates = [
        "What are you doing today?",
        "What are you looking forward to this week?",
        "What's the fit today?",
        "What's one small win you had recently?",
        "What song has been stuck in your head?",
        "What's your go-to snack right now?",
        "What are you watching, reading, or listening to?",
        "What made you laugh today?",
        "What is one thing you want to get done today?",
        "What are you grateful for this morning?",
        "What's your current comfort food?",
        "What are you most excited to do after work or school?",
        "What's something you noticed today?",
        "How would you describe your mood in three words?",
        "What's one thing making life easier this week?",
        "What was the best part of your day yesterday?",
        "What's a tiny thing you are treating yourself to?",
        "What are you currently learning?",
        "What is your current favorite place to be?",
        "What are you hoping tomorrow feels like?"
    ]

    private static let deepByMonth: [[String]] = [
        ["How is your year going so far?", "What do you want to protect more of this year?", "What is one goal you want to make easier, not harder?", "What are you most looking forward to this year?"],
        ["What kind of love or friendship do you want to give more of?", "What does feeling supported look like to you?", "What are you proud of yourself for lately?", "If you had one extra free day this month, how would you use it?"],
        ["What is changing in your life right now?", "What does a good reset look like for you?", "What habit is actually helping you?", "Where do you want to be more patient with yourself?"],
        ["What are you ready to grow out of?", "What would make this spring feel meaningful?", "What is one risk that feels worth taking?", "What part of your routine deserves more care?"],
        ["If you could try any profession for a year, what would it be?", "What do you want to remember about this season of life?", "What does success mean to you right now?", "What are you curious enough to explore?"],
        ["What has surprised you about this year?", "What does rest mean to you lately?", "What would you tell your younger self at this point in life?", "What do you want more time for this summer?"],
        ["What are you most proud of from the first half of the year?", "What would make the next six months feel good?", "What do you want to be more intentional about?", "What is one way you have changed recently?"],
        ["What are you ready to say yes to?", "What helps you feel at home?", "What is a belief you have changed your mind about?", "Where do you want to show up more boldly?"],
        ["What did summer teach you?", "What kind of energy do you want this fall?", "What would help you feel organized without being rigid?", "What are you willing to practice slowly?"],
        ["What feels worth celebrating lately?", "What is one thing you want to finish before the year ends?", "What do you want your future self to thank you for?", "What makes a friendship feel lasting to you?"],
        ["What are you thankful you learned this year?", "What would a peaceful holiday season look like?", "What are you ready to let go of?", "Who has made a difference in your year?"],
        ["What memory from this year do you want to carry forward?", "What did you do this year that took courage?", "What is one gentle goal for next year?", "What are you hopeful about?"
        ]
    ]

    private static let timelyByMonth: [[String]] = [
        ["What is one New Year goal you actually care about?", "What are you keeping from last year?", "What is your ideal cozy winter evening?", "What do you want more of this January?", "What is your January reset ritual?"],
        ["What does a great Super Bowl watch party need?", "Who deserves a little extra appreciation this month?", "What is making winter better for you?", "What is a tiny act of love you have noticed?", "What are you looking forward to when winter ends?"],
        ["What is one sign of spring you are waiting for?", "What would make this month feel lighter?", "What is a tradition you would like to start?", "What is your favorite thing about longer days?", "What are you ready to refresh?"],
        ["What do you love about spring?", "What is your favorite rainy-day plan?", "What are you planting, literally or metaphorically?", "What does a perfect April weekend look like?", "What do you want to make room for this month?"],
        ["What is one thing you want to celebrate this month?", "What would your perfect long weekend look like?", "What are you doing to mark the start of summer?", "What is an underrated May activity?", "What are you looking forward to this Memorial Day season?"],
        ["What is your early-summer mood?", "Are you following the NBA Finals—who are you rooting for?", "What is on your summer bucket list?", "What makes a great summer night?", "What is one thing you want to do before June ends?"],
        ["What is your ideal Fourth of July plan?", "What summer food are you craving?", "What has been the best part of summer so far?", "What is one spontaneous thing you want to do?", "What is your perfect hot-day activity?"],
        ["What is your favorite summer memory?", "What do you want to savor before summer ends?", "What song belongs on your August soundtrack?", "What does a perfect late-summer weekend look like?", "What are you ready to carry into fall?"],
        ["Are you ready for fall, or are you still holding on to summer?", "What did you love most about your summer?", "What is your back-to-school or back-to-routine goal?", "What is your favorite early-fall ritual?", "What are you excited to learn this season?"],
        ["What is the best thing about sweater weather?", "What is on your fall bucket list?", "What makes a cozy night feel complete?", "What costume would you wear if effort did not matter?", "What are you enjoying about this season?"],
        ["What are you thankful for right now?", "What dish are you most excited for at Thanksgiving?", "What is a small kindness you received recently?", "What is one thing you want to appreciate before the year ends?", "What would make this month feel warm and grounded?"],
        ["What do you want for the holidays—big or small?", "What is your favorite holiday tradition?", "What is your best gift-giving idea this year?", "What are you proud to have made it through?", "How do you want to close out the year?"
        ]
    ]

    private static let bonusPrompts = [
        "What is one thing you want this next year of life to bring?",
        "What is a birthday wish you are comfortable sharing?",
        "What is one thing you have learned since your last birthday?",
        "Who made you feel celebrated recently?",
        "What is a place you would love to visit next?",
        "What is the kindest thing someone has said to you?",
        "What is an ordinary moment you want to remember?",
        "What is a tradition your group should start?",
        "What is the best advice you received this year?",
        "What does a perfect day off look like?",
        "What are you optimistic about?",
        "What is a skill you would like to borrow from someone else?",
        "Trivia: Which planet is known as the Red Planet?",
        "Trivia: What is the largest ocean on Earth?",
        "Trivia: Which country gifted the Statue of Liberty to the United States?",
        "Trivia: How many sides does a standard stop sign have?",
        "Trivia: What is the fastest land animal?"
    ]

    private static let triviaQuestions: [(question: String, answers: [String])] = [
        ("Which planet is known as the Red Planet?", ["Mars"]),
        ("What is the largest ocean on Earth?", ["Pacific", "Pacific Ocean"]),
        ("Which element has the chemical symbol W?", ["Tungsten", "Wolfram"]),
        ("In what year did the Berlin Wall fall?", ["1989"]),
        ("Who wrote the novel Frankenstein?", ["Mary Shelley"]),
        ("What is the capital of New Zealand?", ["Wellington"]),
        ("How many sides does a dodecagon have?", ["12", "Twelve"]),
        ("Which artist painted The Starry Night?", ["Vincent van Gogh", "Van Gogh"]),
        ("What is the largest desert on Earth by total area?", ["Antarctica", "Antarctic Desert"]),
        ("Which novel begins with the words Call me Ishmael?", ["Moby Dick", "Moby-Dick"]),
        ("What is the smallest prime number?", ["2", "Two"]),
        ("Which country gifted the Statue of Liberty to the United States?", ["France"]),
        ("What is the chemical symbol for gold?", ["Au"]),
        ("Which language has the most native speakers worldwide?", ["Mandarin", "Mandarin Chinese", "Chinese"]),
        ("What is the name of the galaxy containing our solar system?", ["Milky Way", "The Milky Way"]),
        ("Which organ is the largest in the human body?", ["Skin", "The skin"]),
        ("How many players from one team are on the court in basketball?", ["5", "Five"]),
        ("Which scientist formulated the three laws of motion?", ["Isaac Newton", "Newton"]),
        ("What is the capital of Canada?", ["Ottawa"]),
        ("Which continent contains the most countries?", ["Africa"]),
        ("What is the hardest natural substance?", ["Diamond"]),
        ("Who was the first woman to win a Nobel Prize?", ["Marie Curie", "Curie"]),
        ("What is the longest river in South America?", ["Amazon", "Amazon River"]),
        ("Which composer wrote The Four Seasons?", ["Antonio Vivaldi", "Vivaldi"])
    ]

    static let questions: [DailyPrompt] = {
        var bank: [DailyPrompt] = []

        for month in 0..<12 {
            let monthName = Calendar.current.monthSymbols[month]
            for (index, question) in surfaceTemplates.enumerated() {
                bank.append(DailyPrompt(id: "surface-\(month)-\(index)", question: question, kind: .surface, isNewsletterFeature: false))
            }
            for (index, question) in deepByMonth[month].enumerated() {
                bank.append(DailyPrompt(id: "featured-\(month)-\(index)", question: question, kind: .featured, isNewsletterFeature: true))
            }
            for (index, question) in timelyByMonth[month].enumerated() {
                bank.append(DailyPrompt(id: "timely-\(monthName)-\(index)", question: question, kind: .timely, isNewsletterFeature: false))
            }
        }

        for (index, question) in bonusPrompts.enumerated() {
            let kind: PromptKind = index >= 12 ? .trivia : .birthday
            bank.append(DailyPrompt(id: "bonus-\(index)", question: question, kind: kind, isNewsletterFeature: false))
        }

        return bank
    }()

    static func prompt(for date: Date = .now, birthdayPrompt: String? = nil, birthday: Date? = nil) -> DailyPrompt {
        let calendar = pacificCalendar
        let effectiveDate = contentDate(for: date)

        if let holidayPrompt = fixedHolidayPrompt(for: effectiveDate, calendar: calendar) {
            return holidayPrompt
        }

        if let pollPrompt = monthlyPollPrompt(for: effectiveDate, calendar: calendar) {
            return pollPrompt
        }

        if let newsletterPrompt = monthlyNewsletterPrompt(for: effectiveDate, calendar: calendar) {
            return newsletterPrompt
        }

        if let photoPrompt = monthlyPhotoPrompt(for: effectiveDate, calendar: calendar) {
            return photoPrompt
        }

        let thursdayNumber = (calendar.component(.day, from: effectiveDate) - 1) / 7 + 1
        if calendar.component(.weekday, from: effectiveDate) == 5 && thursdayNumber <= 4 {
            return weeklyTriviaForEffectiveDate(effectiveDate)
        }

        if let birthday, calendar.component(.month, from: birthday) == calendar.component(.month, from: effectiveDate), calendar.component(.day, from: birthday) == calendar.component(.day, from: effectiveDate) {
            let custom = birthdayPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DailyPrompt(id: "birthday-today", question: custom?.isEmpty == false ? custom! : bonusPrompts[0], kind: .birthday, isNewsletterFeature: false)
        }

        let month = calendar.component(.month, from: effectiveDate) - 1
        let monthlyQuestions = questions.filter {
            $0.kind != .featured && ($0.id.contains("-\(month)-") || $0.id.contains("-\(Calendar.current.monthSymbols[month])-"))
        }
        let day = calendar.component(.day, from: effectiveDate) - 1
        return monthlyQuestions[day % monthlyQuestions.count]
    }

    private static func fixedHolidayPrompt(for date: Date, calendar: Calendar) -> DailyPrompt? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        if month == 7 && day == 4 {
            return DailyPrompt(
                id: "holiday-\(year)-july-4",
                question: "How are you celebrating the Fourth of July?",
                kind: .timely,
                isNewsletterFeature: false
            )
        }

        if month == 5 && day == 31 {
            return DailyPrompt(
                id: "seasonal-\(year)-summer-preview",
                question: "What are you excited about for summer?",
                kind: .timely,
                isNewsletterFeature: false
            )
        }

        if month == 3 && day == 1 {
            return DailyPrompt(
                id: "seasonal-\(year)-winter-recap",
                question: "How was your winter?",
                kind: .featured,
                isNewsletterFeature: true
            )
        }

        if month == 6 && day == 1 {
            return DailyPrompt(
                id: "seasonal-\(year)-spring-recap",
                question: "How was your spring?",
                kind: .featured,
                isNewsletterFeature: true
            )
        }

        if month == 9 && day == 1 {
            return DailyPrompt(
                id: "seasonal-\(year)-summer-recap",
                question: "How was your summer?",
                kind: .featured,
                isNewsletterFeature: true
            )
        }

        if month == 11 && day == 30 {
            return DailyPrompt(
                id: "seasonal-\(year)-fall-recap",
                question: "How was your fall?",
                kind: .featured,
                isNewsletterFeature: true
            )
        }

        var superBowlComponents = DateComponents()
        superBowlComponents.calendar = calendar
        superBowlComponents.timeZone = calendar.timeZone
        superBowlComponents.year = year
        superBowlComponents.month = 2
        superBowlComponents.weekday = 1
        superBowlComponents.weekdayOrdinal = 2

        if let superBowlSunday = calendar.date(from: superBowlComponents),
           calendar.isDate(date, inSameDayAs: superBowlSunday) {
            return DailyPrompt(
                id: "holiday-\(year)-super-bowl",
                question: "Who do you think is going to win the Super Bowl?",
                kind: .timely,
                isNewsletterFeature: false
            )
        }

        if month == 12 && day == 25 {
            return DailyPrompt(
                id: "holiday-\(year)-christmas",
                question: "What do you want for Christmas?",
                kind: .timely,
                isNewsletterFeature: true
            )
        }

        var thanksgivingComponents = DateComponents()
        thanksgivingComponents.calendar = calendar
        thanksgivingComponents.timeZone = calendar.timeZone
        thanksgivingComponents.year = year
        thanksgivingComponents.month = 11
        thanksgivingComponents.weekday = 5
        thanksgivingComponents.weekdayOrdinal = 4

        if let thanksgiving = calendar.date(from: thanksgivingComponents),
           let thanksgivingEve = calendar.date(byAdding: .day, value: -1, to: thanksgiving),
           calendar.isDate(date, inSameDayAs: thanksgivingEve) {
            return DailyPrompt(
                id: "holiday-\(year)-thanksgiving-eve",
                question: "What are you grateful for?",
                kind: .timely,
                isNewsletterFeature: true
            )
        }

        return nil
    }

    private static func monthlyPollPrompt(for date: Date, calendar: Calendar) -> DailyPrompt? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.weekday = 3
        components.weekdayOrdinal = 2

        guard let pollDay = calendar.date(from: components),
              calendar.isDate(date, inSameDayAs: pollDay) else { return nil }

        let polls: [(String, [String])] = [
            ("What is the ideal way to spend a free Saturday?", ["Stay in", "Go out", "A little of both"]),
            ("Which meal deserves the most effort?", ["Breakfast", "Lunch", "Dinner"]),
            ("When do you feel most like yourself?", ["Morning", "Afternoon", "Late at night"]),
            ("Pick the group’s next adventure.", ["Beach day", "Game night", "New restaurant", "Road trip"])
        ]
        let poll = polls[(month - 1) % polls.count]
        return DailyPrompt(
            id: "poll-\(year)-\(month)",
            question: poll.0,
            kind: .surface,
            isNewsletterFeature: false,
            pollOptions: poll.1
        )
    }

    private static func monthlyNewsletterPrompt(for date: Date, calendar: Calendar) -> DailyPrompt? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)

        for ordinal in 1...4 {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.weekday = 4
            components.weekdayOrdinal = ordinal
            guard let promptDate = calendar.date(from: components),
                  calendar.isDate(date, inSameDayAs: promptDate) else { continue }
            let question = deepByMonth[month - 1][ordinal - 1]
            return DailyPrompt(
                id: "newsletter-\(year)-\(month)-\(ordinal)",
                question: question,
                kind: .featured,
                isNewsletterFeature: true
            )
        }
        return nil
    }

    private static func monthlyPhotoPrompt(for date: Date, calendar: Calendar) -> DailyPrompt? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let prompts = [
            (1, "Share a photo from this month that includes you."),
            (3, "Share a photo of the best food you had this month.")
        ]

        for (ordinal, question) in prompts {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.weekday = 1
            components.weekdayOrdinal = ordinal
            guard let promptDate = calendar.date(from: components),
                  calendar.isDate(date, inSameDayAs: promptDate) else { continue }
            return DailyPrompt(
                id: "hidden-report-photo-\(year)-\(month)-\(ordinal)",
                question: question,
                kind: .featured,
                isNewsletterFeature: true
            )
        }
        return nil
    }

    static func weeklyTrivia(for date: Date = .now) -> DailyPrompt {
        weeklyTriviaForEffectiveDate(contentDate(for: date))
    }

    private static func weeklyTriviaForEffectiveDate(_ date: Date) -> DailyPrompt {
        let calendar = pacificCalendar
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let thursdayNumber = min(4, (calendar.component(.day, from: date) - 1) / 7 + 1)
        let index = abs((year * 48) + ((month - 1) * 4) + thursdayNumber - 1) % triviaQuestions.count
        let trivia = triviaQuestions[index]
        return DailyPrompt(
            id: "thursday-trivia-\(year)-\(month)-\(thursdayNumber)",
            question: trivia.question,
            kind: .trivia,
            isNewsletterFeature: true,
            acceptedAnswers: trivia.answers
        )
    }
}
