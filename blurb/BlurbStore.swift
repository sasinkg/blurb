import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

struct BlurbGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let ownerID: String
    let memberIDs: [String]
    let inviteCode: String
    var isExample = false

    var memberCount: Int { memberIDs.count }
    // Example participants are presentation fixtures, never Firebase members.
    var sampleParticipantCount: Int { isExample ? ExampleGroupContent.posts.count : 0 }
    var displayedParticipantCount: Int { memberCount + sampleParticipantCount }
}

struct BlurbPost: Identifiable, Hashable {
    let id: String
    let entryID: String
    let groupID: String
    let authorID: String
    let authorName: String
    let authorPhotoURL: String?
    let imageURL: String?
    let answer: String
    let prompt: String
    let promptID: String
    let pollOptions: [String]
    let isMonthlyReportPrompt: Bool
    let createdAt: Date
    let editedAt: Date?
    let editCount: Int
    let countsTowardStreak: Bool
    let likeIDs: [String]
    let answerRank: Int
    let pointsAwarded: Int
    let commentCount: Int
    var isSample = false

    var likeCount: Int { likeIDs.count }
    var effectivePostedAt: Date { editedAt ?? createdAt }
    var placementLabel: String? {
        switch answerRank {
        case 1: return "1st place!"
        case 2: return "2nd place"
        case 3: return "3rd place"
        default: return nil
        }
    }
    var timeLabel: String {
        let date = editedAt ?? createdAt
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        let prefix = editedAt == nil ? "" : "Edited "
        if minutes < 1 { return "\(prefix)just now" }
        if minutes < 60 { return "\(prefix)\(minutes)m ago" }
        if minutes < 1_440 { return "\(prefix)\(minutes / 60)h ago" }
        return "\(prefix)\(minutes / 1_440)d ago"
    }
}

struct BlurbComment: Identifiable, Hashable {
    let id: String
    let authorID: String
    let authorName: String
    let authorPhotoURL: String?
    let text: String
    let createdAt: Date
    var likeIDs: [String] = []
}

struct MonthlyWinner {
    let title: String
    let points: Int
}

struct BlurbProfile {
    var displayName: String = "Blurb friend"
    var photoURL: String?
}

struct NewsletterEntry: Identifiable, Hashable {
    let id: String
    let authorName: String
    let answer: String
    let prompt: String
    let promptID: String
    let imageURL: String?
    let createdAt: Date
}

struct NewsletterEdition: Identifiable, Hashable {
    let id: String
    let groupID: String
    let groupName: String
    let monthKey: String
    let monthLabel: String
    let entries: [NewsletterEntry]
    let mostAnswersWinner: String?
    let mostPointsWinner: String?
}

@MainActor
final class BlurbStore: ObservableObject {
    @Published private(set) var groups: [BlurbGroup] = []
    @Published private(set) var groupsLoaded = false
    @Published private(set) var posts: [BlurbPost] = []
    @Published private(set) var answerCountsByGroup: [String: Int] = [:]
    @Published private(set) var myAnswerStatusByGroup: [String: Bool] = [:]
    @Published private(set) var profile = BlurbProfile()
    @Published private(set) var profileLoaded = false
    @Published private(set) var needsProfileSetup = false
    @Published private(set) var commentsByPostID: [String: [BlurbComment]] = [:]
    @Published private(set) var newsletterEditions: [NewsletterEdition] = []
    @Published private(set) var photoOfMonthSelections: [String: PhotoOfMonthSelection] = [:]
    @Published var selectedGroupID: String?
    @Published var errorMessage: String?
    @Published private(set) var listenerErrorMessage: String?

    private let database = Firestore.firestore()
    private var groupsListener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var newsletterListener: ListenerRegistration?
    private var photoOfMonthListener: ListenerRegistration?
    private var answerCountListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var currentUserID: String?
    private var activeAnswerCountPromptID: String?
    private var listenerGeneration = 0
    private var listenerErrors: [String: String] = [:]
#if DEBUG
    private var isAppStoreScreenshotFixture = false
#endif

    var canAddReviewExamples: Bool {
        guard let currentUserID else { return false }
        return !ReviewConfiguration.accountUID.isEmpty && currentUserID == ReviewConfiguration.accountUID
    }

    var selectedGroup: BlurbGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var currentStreak: Int {
        guard let userID = currentUserID else { return 0 }
        let calendar = Calendar.current
        let answeredDays = Set(posts
            .filter { $0.authorID == userID && $0.countsTowardStreak }
            .map { calendar.startOfDay(for: $0.createdAt) })
        var streak = 0
        var day = calendar.startOfDay(for: .now)
        while answeredDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return streak
    }

    func hasAnswered(promptID: String, in groupID: String? = nil) -> Bool {
        guard let userID = currentUserID else { return false }
        let targetGroupID = groupID ?? selectedGroupID
        return posts.contains {
            !$0.isSample && $0.authorID == userID && $0.promptID == promptID && $0.groupID == targetGroupID
        }
    }

    func answer(for promptID: String, in groupID: String? = nil) -> BlurbPost? {
        guard let userID = currentUserID else { return nil }
        let targetGroupID = groupID ?? selectedGroupID
        return posts.first {
            !$0.isSample && $0.authorID == userID && $0.promptID == promptID && $0.groupID == targetGroupID
        }
    }

    func photoPostsForCurrentMonth(in groupID: String) -> [BlurbPost] {
        guard let userID = currentUserID else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return posts.filter {
            !$0.isSample && $0.groupID == groupID && $0.authorID == userID
                && $0.imageURL != nil && calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .month)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func photoOfMonthSelection(in groupID: String) -> PhotoOfMonthSelection? {
        photoOfMonthSelections[Self.photoSelectionID(groupID: groupID)]
    }

    func selectPhotoOfMonth(_ post: BlurbPost) async -> Bool {
        do {
            _ = try await Functions.functions().httpsCallable("setPhotoOfMonthSelection")
                .call(["groupID": post.groupID, "postID": post.id])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func photoSelectionID(groupID: String, date: Date = .now) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%@_%04d-%02d", groupID, parts.year ?? 0, parts.month ?? 0)
    }

    func existingAnswer(promptID: String, in groupID: String) async -> BlurbPost? {
        guard let userID = currentUserID else { return nil }
        if let loadedAnswer = answer(for: promptID, in: groupID) {
            return loadedAnswer
        }

        do {
            let snapshot = try await database.collection("posts")
                .whereField("groupID", isEqualTo: groupID)
                .whereField("promptID", isEqualTo: promptID)
                .whereField("authorID", isEqualTo: userID)
                .limit(to: 1)
                .getDocuments()
            return snapshot.documents.first.flatMap { Self.makePost($0) }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    var currentMonthPoints: Int {
        guard let userID = currentUserID else { return 0 }
        let calendar = Calendar.current
        return posts
            .filter { $0.authorID == userID && calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.pointsAwarded }
    }

    var lastMonthWinner: MonthlyWinner? {
        guard let userID = currentUserID else { return nil }
        let calendar = Calendar.current
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: .now) else { return nil }
        let lastMonthPosts = posts.filter { calendar.isDate($0.createdAt, equalTo: lastMonth, toGranularity: .month) }
        let totals = Dictionary(grouping: lastMonthPosts, by: \.authorID)
            .mapValues { $0.reduce(0) { $0 + $1.pointsAwarded } }
        guard let highestScore = totals.values.max(),
              totals[userID] == highestScore,
              highestScore > 0 else { return nil }
        return MonthlyWinner(
            title: "\(lastMonth.formatted(.dateTime.month(.wide))) winner",
            points: highestScore
        )
    }

    func start(for userID: String) {
        guard currentUserID != userID else { return }
        stop()
        currentUserID = userID
        errorMessage = nil
        let generation = listenerGeneration

        groupsListener = database.collection("groups")
            .whereField("memberIDs", arrayContains: userID)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, self.listenerGeneration == generation else { return }
                if let error {
                    Task { @MainActor in
                        guard self.listenerGeneration == generation else { return }
                        self.recordListenerError(error, source: "groups")
                    }
                    return
                }
                // Dependent queries are authorized through the committed group.
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                let groups = snapshot.documents.compactMap(Self.makeGroup)
                Task { @MainActor in
                    guard self.listenerGeneration == generation else { return }
                    self.clearListenerError(source: "groups")
                    self.groups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.groupsLoaded = true
                    if self.selectedGroupID == nil || !groups.contains(where: { $0.id == self.selectedGroupID }) {
                        self.selectedGroupID = groups.first?.id
                    }
                    self.listenForPosts()
                    if let promptID = self.activeAnswerCountPromptID {
                        self.listenForAnswerCounts(promptID: promptID)
                    }
                    self.ensureInviteRecords(from: snapshot.documents, userID: userID)
                }
            }

        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.listenerGeneration == generation else { return }
                    if let error {
                        self.recordListenerError(error, source: "profile")
                        return
                    }
                    guard let snapshot else { return }
                    let data = snapshot.data() ?? [:]
                    let name = data["displayName"] as? String ?? "Blurb friend"
                    self.profile = BlurbProfile(displayName: name, photoURL: data["photoURL"] as? String)
                    // Preserve completed legacy profiles; unfinished accounts resume
                    // setup even after signing out or reinstalling the app.
                    let legacyComplete = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "Blurb friend"
                    self.needsProfileSetup = !(data["profileSetupCompleted"] as? Bool ?? legacyComplete)
                    self.profileLoaded = true
                    self.clearListenerError(source: "profile")
                }
            }

        newsletterListener = database.collection("newsletterEditions")
            .whereField("viewerIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.listenerGeneration == generation else { return }
                if let error {
                    Task { @MainActor in
                        self.recordListenerError(error, source: "newsletter-editions")
                    }
                    return
                }
                let editions = snapshot?.documents.compactMap(Self.makeNewsletterEdition) ?? []
                Task { @MainActor in
                    self.clearListenerError(source: "newsletter-editions")
                    self.newsletterEditions = editions.sorted { $0.monthKey > $1.monthKey }
                }
            }

        photoOfMonthListener = database.collection("users").document(userID)
            .collection("photoOfMonthSelections")
            .addSnapshotListener { [weak self] snapshot, _ in
                let selections = snapshot?.documents.compactMap(Self.makePhotoOfMonthSelection) ?? []
                Task { @MainActor in
                    self?.photoOfMonthSelections = Dictionary(uniqueKeysWithValues: selections.map { ($0.id, $0) })
                }
            }
    }

    func invalidateListeners() {
        listenerGeneration += 1
        currentUserID = nil
        groupsListener?.remove(); groupsListener = nil
        postsListener?.remove(); postsListener = nil
        profileListener?.remove(); profileListener = nil
        newsletterListener?.remove(); newsletterListener = nil
        photoOfMonthListener?.remove(); photoOfMonthListener = nil
        answerCountListeners.values.forEach { $0.remove() }
        answerCountListeners = [:]
        commentListeners.values.forEach { $0.remove() }
        commentListeners = [:]
        listenerErrors = [:]
        listenerErrorMessage = nil
    }

    func stop() {
        invalidateListeners()
        currentUserID = nil
        activeAnswerCountPromptID = nil
        profile = BlurbProfile()
        profileLoaded = false
        needsProfileSetup = false
        groups = []; groupsLoaded = false; posts = []; answerCountsByGroup = [:]; myAnswerStatusByGroup = [:]; commentsByPostID = [:]; newsletterEditions = []; photoOfMonthSelections = [:]; selectedGroupID = nil
        errorMessage = nil
        listenerErrors = [:]
        listenerErrorMessage = nil
    }

    func listenForAnswerCounts(promptID: String) {
#if DEBUG
        if isAppStoreScreenshotFixture { return }
#endif
        guard currentUserID != nil else { return }
        let generation = listenerGeneration
        activeAnswerCountPromptID = promptID
        clearListenerErrors(withPrefix: "answer-count-")
        answerCountListeners.values.forEach { $0.remove() }
        answerCountListeners = [:]
        answerCountsByGroup = [:]
        myAnswerStatusByGroup = [:]

        for group in groups {
            answerCountListeners[group.id] = database.collection("posts")
                .whereField("groupID", isEqualTo: group.id)
                .whereField("promptID", isEqualTo: promptID)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self, self.listenerGeneration == generation else { return }
                    if let error {
                        Task { @MainActor in
                            guard self.listenerGeneration == generation else { return }
                            self.recordListenerError(error, source: "answer-count-\(group.id)")
                        }
                        return
                    }
                    guard let snapshot else { return }
                    let uniqueAuthors = Set(snapshot.documents.compactMap { document -> String? in
                        guard document.data()["isSample"] as? Bool != true else { return nil }
                        return document.data()["authorID"] as? String
                    })
                    Task { @MainActor in
                        guard self.listenerGeneration == generation else { return }
                        self.clearListenerError(source: "answer-count-\(group.id)")
                        guard self.activeAnswerCountPromptID == promptID else { return }
                        self.answerCountsByGroup[group.id] = uniqueAuthors.count
                        self.myAnswerStatusByGroup[group.id] = uniqueAuthors.contains(self.currentUserID ?? "")
                    }
                }
        }
    }

    func answerCount(in groupID: String) -> Int {
        answerCountsByGroup[groupID, default: 0]
    }

    func displayedAnswerCount(in group: BlurbGroup) -> Int {
        answerCount(in: group.id) + group.sampleParticipantCount
    }

    func currentAnswerRank(for post: BlurbPost) -> Int {
        guard !post.isSample else { return 0 }
        let rankedPosts = posts
            .filter { !$0.isSample && $0.groupID == post.groupID && $0.promptID == post.promptID }
            .sorted {
                if $0.effectivePostedAt == $1.effectivePostedAt { return $0.id < $1.id }
                return $0.effectivePostedAt < $1.effectivePostedAt
            }
        return rankedPosts.firstIndex(where: { $0.id == post.id }).map { $0 + 1 } ?? post.answerRank
    }

    var myAchievements: [AchievementProgress] {
        achievements(for: currentUserID ?? "", in: selectedGroupID ?? "")
    }

    func achievements(for userID: String, in groupID: String) -> [AchievementProgress] {
        AchievementProgress.calculate(posts: posts, userID: userID, groupID: groupID)
    }

    func memberProfiles(in groupID: String) -> [GroupMemberProfile] {
        guard let group = groups.first(where: { $0.id == groupID }) else { return [] }
        var members: [String: GroupMemberProfile] = [:]
        for post in posts.filter({ $0.groupID == groupID && !$0.isSample }).sorted(by: { $0.createdAt < $1.createdAt }) {
            for comment in commentsByPostID[post.id] ?? [] {
                members[comment.authorID] = GroupMemberProfile(id: comment.authorID, name: comment.authorName, photoURL: comment.authorPhotoURL)
            }
            members[post.authorID] = GroupMemberProfile(id: post.authorID, name: post.authorName, photoURL: post.authorPhotoURL)
        }
        if let userID = currentUserID {
            members[userID] = GroupMemberProfile(id: userID, name: profile.displayName, photoURL: profile.photoURL)
        }
        return members.values.filter { group.memberIDs.contains($0.id) }.sorted { $0.name < $1.name }
    }

    func mentionNames(in groupID: String? = nil) -> [String] {
        let target = groupID ?? selectedGroupID
        let members = groups.first { $0.id == target }?.memberIDs ?? []
        let names = posts.filter { $0.groupID == target && !$0.isSample && members.contains($0.authorID) }
            .map(\.authorName) + [profile.displayName]
        return Array(Set(names)).sorted()
    }

    func select(_ group: BlurbGroup) {
        selectedGroupID = group.id
        listenForPosts()
    }

    func createGroup(named rawName: String, isExample: Bool = false) async -> Bool {
        guard let userID = currentUserID else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            let reference = database.collection("groups").document()
            let inviteCode = Self.makeInviteCode()
            let batch = database.batch()
            batch.setData([
                "name": name,
                "isExample": isExample,
                "ownerID": userID,
                "memberIDs": [userID],
                "inviteCode": inviteCode,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: reference)
            batch.setData([
                "groupID": reference.documentID,
                "ownerID": userID,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: database.collection("groupInvites").document(inviteCode))
            try await batch.commit()
            let newGroup = BlurbGroup(
                id: reference.documentID,
                name: name,
                ownerID: userID,
                memberIDs: [userID],
                inviteCode: inviteCode,
                isExample: isExample
            )
            if !groups.contains(where: { $0.id == newGroup.id }) {
                groups.append(newGroup)
                groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            groupsLoaded = true
            selectedGroupID = reference.documentID
            listenForPosts()
            if let promptID = activeAnswerCountPromptID {
                listenForAnswerCounts(promptID: promptID)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reuses an owned example group and fills only missing sample documents.
    /// No existing posts, likes, or replies are overwritten.
    func addExampleGroup() async -> Bool {
        guard let userID = currentUserID, canAddReviewExamples else { return false }
        do {
            let memberships = try await database.collection("groups")
                .whereField("memberIDs", arrayContains: userID).getDocuments()
            let existingGroup = memberships.documents.first {
                $0.data()["isExample"] as? Bool == true && $0.data()["ownerID"] as? String == userID
            }
            let groupID: String
            if let existingGroup {
                groupID = existingGroup.documentID
            } else {
                guard await createGroup(named: "Example group", isExample: true),
                      let createdGroupID = selectedGroupID else { return false }
                groupID = createdGroupID
            }
            // The group must be committed before membership rules allow posts.
            let samples = ExampleGroupContent.posts
            let references = samples.map { database.collection("posts").document("\(groupID)_\($0.id)") }
            let comments = references.map { $0.collection("comments").document("sample-reply") }
            // Query by group because read rules cannot authorize a missing post
            // document (it has no groupID yet). A retry preserves existing samples.
            let existingPosts = try await database.collection("posts")
                .whereField("groupID", isEqualTo: groupID).getDocuments()
            let existingIDs = Set(existingPosts.documents.map(\.documentID))
            let batch = database.batch()
            for (index, sample) in samples.enumerated() where !existingIDs.contains(references[index].documentID) {
                batch.setData([
                    "entryID": references[index].documentID,
                    "groupID": groupID, "authorID": userID,
                    "authorName": "\(sample.name) · Example",
                    "viewerIDs": [userID], "answer": sample.answer,
                    "prompt": sample.prompt, "promptID": "example-\(sample.id)",
                    "pollOptions": [], "isMonthlyReportPrompt": true,
                    "createdAt": Timestamp(date: Date.now.addingTimeInterval(Double(-index * 300))),
                    "editCount": 0, "countsTowardStreak": false,
                    "likeIDs": [], "commentCount": 0,
                    "answerRank": 0, "pointsAwarded": 0, "isSample": true
                ], forDocument: references[index])
            }
            try await batch.commit()
            // Comment rules read the parent post, so seed replies only after the
            // posts commit. This also lets interrupted setup resume safely.
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let parents = try references.map { try transaction.getDocument($0) }
                    let existingComments = try comments.map { try transaction.getDocument($0) }
                    for (index, sample) in samples.enumerated() where !existingComments[index].exists {
                        guard parents[index].exists else { continue }
                        transaction.setData([
                            "authorID": userID, "authorName": "Sample reply",
                            "text": sample.comment, "createdAt": FieldValue.serverTimestamp()
                        ], forDocument: comments[index])
                        transaction.updateData(["commentCount": FieldValue.increment(Int64(1))], forDocument: references[index])
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            selectedGroupID = groupID
            listenForPosts()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't add the example group. Try again to finish setting it up. \(error.localizedDescription)"
            return false
        }
    }

    func joinGroup(with rawCode: String) async -> Bool {
        guard let userID = currentUserID else { return false }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return false }
        do {
            let invite = try await database.collection("groupInvites").document(code).getDocument()
            guard let groupID = invite.data()?["groupID"] as? String else {
                errorMessage = "That group code wasn’t found. Check it and try again."
                return false
            }
            try await database.collection("groups").document(groupID)
                .updateData(["memberIDs": FieldValue.arrayUnion([userID])])
            selectedGroupID = groupID
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateGroup(_ group: BlurbGroup, name rawName: String) async -> Bool {
        guard let userID = currentUserID, group.ownerID == userID else {
            errorMessage = "Only the group owner can rename this group."
            return false
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            try await database.collection("groups").document(group.id).updateData(["name": name])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func canEdit(_ group: BlurbGroup) -> Bool {
        group.ownerID == currentUserID
    }

    func deleteGroup(_ group: BlurbGroup) async -> Bool {
        guard let userID = currentUserID, group.ownerID == userID else {
            errorMessage = "Only the group owner can delete this group."
            return false
        }

        do {
            let groupPosts = try await database.collection("posts")
                .whereField("groupID", isEqualTo: group.id)
                .getDocuments()

            for post in groupPosts.documents {
                let comments = try await post.reference.collection("comments").getDocuments()
                for comment in comments.documents {
                    try await comment.reference.delete()
                }

                let data = post.data()
                if data["imageURL"] as? String != nil,
                   let authorID = data["authorID"] as? String {
                    try? await Storage.storage().reference()
                        .child("post-images/\(group.id)/\(authorID)/\(post.documentID).jpg")
                        .delete()
                }
                try await post.reference.delete()
            }

            try? await database.collection("groupInvites").document(group.inviteCode).delete()
            try await database.collection("groups").document(group.id).delete()
            if selectedGroupID == group.id { selectedGroupID = nil }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createPost(answer: String, imageData: Data? = nil, prompt: DailyPrompt, in groupID: String? = nil) async -> Bool {
        guard let userID = currentUserID,
              let targetGroupID = groupID ?? selectedGroupID,
              groups.contains(where: { $0.id == targetGroupID }) else {
            errorMessage = "Create a group before posting."
            return false
        }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty || (prompt.requiresPhoto && imageData != nil) else { return false }
        guard !hasAnswered(promptID: prompt.id, in: targetGroupID) else {
            errorMessage = "You've already answered today's Daily Blurb in this group. You can edit or delete it from the feed."
            return false
        }
        do {
            // Each group is its own conversation, so the same person may give
            // a different answer to the same prompt in every group.
            let entryID = "\(prompt.id)_\(userID)_\(targetGroupID)"
            // A post can be shared into a group whose feed is not loaded locally.
            // Read that group's actual answers instead of treating an empty local feed as first place.
            let groupSnapshot = try await database.collection("posts")
                .whereField("groupID", isEqualTo: targetGroupID)
                .getDocuments(source: .server)
            let answerRank = groupSnapshot.documents.compactMap(Self.makePost)
                .filter { !$0.isSample && $0.promptID == prompt.id }.count + 1
            let pointsAwarded = Self.points(for: answerRank)
            var sharedValues: [String: Any] = [
                "entryID": entryID,
                "authorID": userID,
                "authorName": profile.displayName,
                "answer": trimmedAnswer,
                "prompt": prompt.question,
                "promptID": prompt.id,
                "pollOptions": prompt.pollOptions,
                "isMonthlyReportPrompt": prompt.isNewsletterFeature,
                "createdAt": FieldValue.serverTimestamp(),
                "editCount": 0,
                "countsTowardStreak": true,
                "likeIDs": [],
                "commentCount": 0,
                "answerRank": answerRank,
                "pointsAwarded": pointsAwarded
            ]
            if let group = groups.first(where: { $0.id == targetGroupID }) {
                sharedValues["viewerIDs"] = group.memberIDs
            }
            if let photoURL = profile.photoURL { sharedValues["authorPhotoURL"] = photoURL }

            if let imageData {
                let imageReference = Storage.storage().reference()
                    .child("post-images/\(targetGroupID)/\(userID)/\(entryID).jpg")
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                _ = try await imageReference.putDataAsync(imageData, metadata: metadata)
                sharedValues["imageURL"] = try await imageReference.downloadURL().absoluteString
            }

            sharedValues["groupID"] = targetGroupID
            let reference = database.collection("posts").document(entryID)
            try await reference.setData(sharedValues)
            if UserDefaults.standard.bool(forKey: "dailyReminderEnabled") {
                NotificationManager.shared.markAnsweredToday()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleLike(_ post: BlurbPost) async {
        guard let userID = currentUserID else { return }
        let fieldValue: FieldValue = post.likeIDs.contains(userID)
            ? .arrayRemove([userID])
            : .arrayUnion([userID])
        do {
            try await database.collection("posts").document(post.id).updateData(["likeIDs": fieldValue])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func listenForComments(on post: BlurbPost) {
#if DEBUG
        if isAppStoreScreenshotFixture { return }
#endif
        commentListeners[post.id]?.remove()
        let generation = listenerGeneration
        commentListeners[post.id] = database.collection("posts").document(post.id)
            .collection("comments")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.listenerGeneration == generation else { return }
                if let error {
                    Task { @MainActor in
                        guard self.listenerGeneration == generation else { return }
                        self.recordListenerError(error, source: "comments-\(post.id)")
                    }
                    return
                }
                let comments = snapshot?.documents.compactMap(Self.makeComment) ?? []
                Task { @MainActor in
                    guard self.listenerGeneration == generation else { return }
                    self.clearListenerError(source: "comments-\(post.id)")
                    self.commentsByPostID[post.id] = comments
                }
            }
    }

    func stopListeningForComments(on postID: String) {
        commentListeners[postID]?.remove()
        commentListeners[postID] = nil
        clearListenerError(source: "comments-\(postID)")
    }

    func deleteComment(_ comment: BlurbComment, on post: BlurbPost) async {
        guard let userID = currentUserID, comment.authorID == userID else { return }
        let postRef = database.collection("posts").document(post.id)
        let commentRef = postRef.collection("comments").document(comment.id)
        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let reply = try transaction.getDocument(commentRef)
                    let parent = try transaction.getDocument(postRef)
                    guard reply.exists, reply.data()?["authorID"] as? String == userID else { return nil }
                    let count = parent.data()?["commentCount"] as? Int ?? 0
                    transaction.deleteDocument(commentRef)
                    if count > 0 { transaction.updateData(["commentCount": count - 1], forDocument: postRef) }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func editComment(_ comment: BlurbComment, on post: BlurbPost, text: String) async -> Bool {
        guard comment.authorID == currentUserID else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1000 else { return false }
        do {
            try await database.collection("posts").document(post.id).collection("comments")
                .document(comment.id).updateData(["text": trimmed, "editedAt": FieldValue.serverTimestamp()])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleCommentLike(_ comment: BlurbComment, on post: BlurbPost) async {
        guard let userID = currentUserID else { return }
        do {
            try await database.collection("posts").document(post.id)
                .collection("comments").document(comment.id).updateData([
                    "likeIDs": comment.likeIDs.contains(userID)
                        ? FieldValue.arrayRemove([userID]) : FieldValue.arrayUnion([userID])
                ])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addComment(_ rawText: String, to post: BlurbPost) async -> Bool {
        guard let userID = currentUserID else { return false }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let postReference = database.collection("posts").document(post.id)
        let commentReference = postReference.collection("comments").document()
        var values: [String: Any] = [
            "authorID": userID,
            "authorName": profile.displayName,
            "text": text,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let photoURL = profile.photoURL { values["authorPhotoURL"] = photoURL }

        do {
            let batch = database.batch()
            batch.setData(values, forDocument: commentReference)
            batch.updateData(["commentCount": FieldValue.increment(Int64(1))], forDocument: postReference)
            try await batch.commit()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func editPost(_ post: BlurbPost, answer: String) async -> Bool {
        guard let userID = currentUserID, post.authorID == userID else { return false }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty || post.imageURL != nil else { return false }
        do {
            let changes: [String: Any] = [
                "answer": trimmedAnswer,
                "editedAt": FieldValue.serverTimestamp(),
                "editCount": post.editCount + 1,
                "countsTowardStreak": false
            ]

            try await database.collection("posts").document(post.id).updateData(changes)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func overwritePost(_ post: BlurbPost, answer: String, imageData: Data?) async -> Bool {
        guard let userID = currentUserID, post.authorID == userID else { return false }
        guard post.editCount == 0 else {
            errorMessage = "Each Blurb can only be edited once."
            return false
        }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty || imageData != nil else { return false }

        do {
            var changes: [String: Any] = [
                "answer": trimmedAnswer,
                "editedAt": FieldValue.serverTimestamp(),
                "editCount": 1,
                "countsTowardStreak": false
            ]
            if let imageData {
                let imageReference = Storage.storage().reference()
                    .child("post-images/\(post.groupID)/\(userID)/\(post.entryID).jpg")
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                _ = try await imageReference.putDataAsync(imageData, metadata: metadata)
                changes["imageURL"] = try await imageReference.downloadURL().absoluteString
            }

            try await database.collection("posts").document(post.id).updateData(changes)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost(_ post: BlurbPost) async {
        guard let userID = currentUserID, post.authorID == userID else { return }
        do {
            try await database.collection("posts").document(post.id).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(name rawName: String, imageData: Data?) async -> Bool {
        guard let userID = currentUserID else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            var values: [String: Any] = ["displayName": name, "lastSeenAt": FieldValue.serverTimestamp(), "profileSetupCompleted": true]
            if let imageData {
                let reference = Storage.storage().reference().child("profile-images/\(userID).jpg")
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                _ = try await reference.putDataAsync(imageData, metadata: metadata)
                values["photoURL"] = try await reference.downloadURL().absoluteString
            }
            try await database.collection("users").document(userID).setData(values, merge: true)

            var postProfileValues: [String: Any] = ["authorName": name]
            if let photoURL = values["photoURL"] as? String ?? profile.photoURL {
                postProfileValues["authorPhotoURL"] = photoURL
            }
            for group in groups {
                let authoredPosts = try await database.collection("posts")
                    .whereField("groupID", isEqualTo: group.id)
                    .whereField("authorID", isEqualTo: userID)
                    .getDocuments()
                for post in authoredPosts.documents where post.data()["isSample"] as? Bool != true {
                    try await post.reference.updateData(postProfileValues)
                }
            }

            needsProfileSetup = false
            profile.displayName = name
            if let photoURL = values["photoURL"] as? String {
                profile.photoURL = photoURL
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAccountData() async -> Bool {
        guard let userID = currentUserID else { return false }
        do {
            for group in groups {
                let ownPosts = try await database.collection("posts")
                    .whereField("groupID", isEqualTo: group.id)
                    .whereField("authorID", isEqualTo: userID)
                    .getDocuments()
                for post in ownPosts.documents {
                    try await post.reference.delete()
                    try? await Storage.storage().reference()
                        .child("post-images/\(group.id)/\(userID)/\(post.documentID).jpg")
                        .delete()
                }

                let groupReference = database.collection("groups").document(group.id)
                if group.ownerID == userID {
                    let remainingMembers = group.memberIDs.filter { $0 != userID }
                    if let newOwner = remainingMembers.first {
                        try await database.collection("groupInvites").document(group.inviteCode)
                            .updateData(["ownerID": newOwner])
                        try await groupReference.updateData([
                            "ownerID": newOwner,
                            "memberIDs": remainingMembers
                        ])
                    } else {
                        try? await database.collection("groupInvites").document(group.inviteCode).delete()
                        try await groupReference.delete()
                    }
                } else {
                    try await groupReference.updateData([
                        "memberIDs": FieldValue.arrayRemove([userID])
                    ])
                }
            }

            try? await Storage.storage().reference().child("profile-images/\(userID).jpg").delete()
            try await database.collection("users").document(userID).delete()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func listenForPosts() {
#if DEBUG
        if isAppStoreScreenshotFixture { return }
#endif
        postsListener?.remove()
        guard let groupID = selectedGroupID, currentUserID != nil else { posts = []; return }
        let generation = listenerGeneration
        postsListener = database.collection("posts")
            .whereField("groupID", isEqualTo: groupID)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, self.listenerGeneration == generation else { return }
                if let error {
                    Task { @MainActor in
                        guard self.listenerGeneration == generation else { return }
                        self.recordListenerError(error, source: "posts")
                    }
                    return
                }
                // Feed cards start comment listeners for their reply previews.
                // Do not expose a new local post until its parent is committed.
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                let posts = snapshot.documents.compactMap(Self.makePost)
                    .sorted { $0.createdAt > $1.createdAt }
                Task { @MainActor in
                    guard self.listenerGeneration == generation else { return }
                    self.clearListenerError(source: "posts")
                    self.posts = posts
                }
            }
    }

#if DEBUG
    func seedAppStoreScreenshotData() {
        isAppStoreScreenshotFixture = true
        let userID = "screenshot-user"
        let group = BlurbGroup(
            id: "roomies",
            name: "Roomies",
            ownerID: userID,
            memberIDs: [userID, "maya", "jordan", "sam"],
            inviteCode: "BLURB1"
        )
        let prompt = QuestionBank.prompt(birthdayPrompt: "", birthday: nil)
        let now = Date.now
        currentUserID = userID
        groups = [
            group,
            BlurbGroup(id: "family", name: "Family", ownerID: "maya", memberIDs: [userID, "maya", "sam"], inviteCode: "BLURB2"),
            BlurbGroup(id: "college", name: "College Friends", ownerID: "jordan", memberIDs: [userID, "maya", "jordan", "sam", "alex"], inviteCode: "BLURB3")
        ]
        groupsLoaded = true
        selectedGroupID = group.id
        answerCountsByGroup = ["roomies": 4, "family": 2, "college": 4]
        profile = BlurbProfile(displayName: "Alex", photoURL: nil)
        posts = [
            BlurbPost(id: "post-alex", entryID: "post-alex", groupID: group.id, authorID: userID, authorName: "Alex", authorPhotoURL: nil, imageURL: nil, answer: "A quiet cup of coffee before everyone woke up.", prompt: prompt.question, promptID: prompt.id, pollOptions: [], isMonthlyReportPrompt: false, createdAt: now.addingTimeInterval(-300), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: ["maya", "jordan"], answerRank: 1, pointsAwarded: 3, commentCount: 2),
            BlurbPost(id: "post-maya", entryID: "post-maya", groupID: group.id, authorID: "maya", authorName: "Maya", authorPhotoURL: nil, imageURL: nil, answer: "The coffee shop remembered my order ☕️", prompt: prompt.question, promptID: prompt.id, pollOptions: [], isMonthlyReportPrompt: false, createdAt: now.addingTimeInterval(-240), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: [userID, "sam"], answerRank: 2, pointsAwarded: 2, commentCount: 1),
            BlurbPost(id: "post-jordan", entryID: "post-jordan", groupID: group.id, authorID: "jordan", authorName: "Jordan", authorPhotoURL: nil, imageURL: nil, answer: "Ten minutes of sunshine between meetings.", prompt: prompt.question, promptID: prompt.id, pollOptions: [], isMonthlyReportPrompt: false, createdAt: now.addingTimeInterval(-180), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: ["maya"], answerRank: 3, pointsAwarded: 1, commentCount: 0)
        ]
        commentsByPostID = [
            "post-alex": [
                BlurbComment(id: "comment-1", authorID: "maya", authorName: "Maya", authorPhotoURL: nil, text: "That sounds perfect.", createdAt: now.addingTimeInterval(-120)),
                BlurbComment(id: "comment-2", authorID: "sam", authorName: "Sam", authorPhotoURL: nil, text: "Best part of the morning!", createdAt: now.addingTimeInterval(-60))
            ]
        ]
    }
#endif

    func clearPresentedErrors() {
        errorMessage = nil
        listenerErrors = [:]
        listenerErrorMessage = nil
    }

    private func recordListenerError(_ error: Error, source: String) {
        listenerErrors[source] = error.localizedDescription
        listenerErrorMessage = error.localizedDescription
    }

    private func clearListenerError(source: String) {
        listenerErrors[source] = nil
        listenerErrorMessage = listenerErrors.values.first
    }

    private func clearListenerErrors(withPrefix prefix: String) {
        for source in Array(listenerErrors.keys) where source.hasPrefix(prefix) {
            listenerErrors[source] = nil
        }
        listenerErrorMessage = listenerErrors.values.first
    }

    private static func makeGroup(_ document: QueryDocumentSnapshot) -> BlurbGroup? {
        let data = document.data()
        guard let name = data["name"] as? String,
              let ownerID = data["ownerID"] as? String,
              let memberIDs = data["memberIDs"] as? [String] else { return nil }
        return BlurbGroup(
            id: document.documentID,
            name: name,
            ownerID: ownerID,
            memberIDs: memberIDs,
            inviteCode: data["inviteCode"] as? String ?? inviteCode(for: document.documentID),
            isExample: data["isExample"] as? Bool ?? false
        )
    }

    private static func makePost(_ document: QueryDocumentSnapshot) -> BlurbPost? {
        makePost(id: document.documentID, data: document.data())
    }

    private static func makePost(_ document: DocumentSnapshot) -> BlurbPost? {
        guard let data = document.data() else { return nil }
        return makePost(id: document.documentID, data: data)
    }

    private static func makePost(id: String, data: [String: Any]) -> BlurbPost? {
        guard let groupID = data["groupID"] as? String,
              let authorID = data["authorID"] as? String,
              let authorName = data["authorName"] as? String,
              let answer = data["answer"] as? String,
              let prompt = data["prompt"] as? String else { return nil }
        return BlurbPost(
            id: id,
            entryID: data["entryID"] as? String ?? id,
            groupID: groupID,
            authorID: authorID,
            authorName: authorName,
            authorPhotoURL: data["authorPhotoURL"] as? String,
            imageURL: data["imageURL"] as? String,
            answer: answer,
            prompt: prompt,
            promptID: data["promptID"] as? String ?? "legacy-\(id)",
            pollOptions: data["pollOptions"] as? [String] ?? [],
            isMonthlyReportPrompt: data["isMonthlyReportPrompt"] as? Bool ?? false,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
            editCount: data["editCount"] as? Int ?? 0,
            countsTowardStreak: data["countsTowardStreak"] as? Bool ?? true,
            likeIDs: data["likeIDs"] as? [String] ?? [],
            answerRank: data["answerRank"] as? Int ?? 0,
            pointsAwarded: data["pointsAwarded"] as? Int ?? 0,
            commentCount: data["commentCount"] as? Int ?? 0,
            isSample: data["isSample"] as? Bool ?? false
        )
    }

    private static func makeComment(_ document: QueryDocumentSnapshot) -> BlurbComment? {
        let data = document.data()
        guard let authorID = data["authorID"] as? String,
              let authorName = data["authorName"] as? String,
              let text = data["text"] as? String else { return nil }
        return BlurbComment(
            id: document.documentID,
            authorID: authorID,
            authorName: authorName,
            authorPhotoURL: data["authorPhotoURL"] as? String,
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            likeIDs: data["likeIDs"] as? [String] ?? []
        )
    }

    private static func makePhotoOfMonthSelection(_ document: QueryDocumentSnapshot) -> PhotoOfMonthSelection? {
        let data = document.data()
        guard let groupID = data["groupID"] as? String,
              let monthKey = data["monthKey"] as? String,
              let userID = data["userID"] as? String,
              let postID = data["postID"] as? String,
              let imageURL = data["imageURL"] as? String else { return nil }
        return PhotoOfMonthSelection(
            id: document.documentID, groupID: groupID, monthKey: monthKey, userID: userID,
            postID: postID, imageURL: imageURL, authorName: data["authorName"] as? String ?? "Blurb friend",
            postCreatedAt: (data["postCreatedAt"] as? Timestamp)?.dateValue() ?? .now,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now
        )
    }

    private static func makeNewsletterEdition(_ document: QueryDocumentSnapshot) -> NewsletterEdition? {
        let data = document.data()
        guard let groupID = data["groupID"] as? String,
              let groupName = data["groupName"] as? String,
              let monthKey = data["monthKey"] as? String,
              let monthLabel = data["monthLabel"] as? String else { return nil }
        let entries = (data["entries"] as? [[String: Any]] ?? []).compactMap { entry -> NewsletterEntry? in
            guard let postID = entry["postID"] as? String,
                  let authorName = entry["authorName"] as? String,
                  let prompt = entry["prompt"] as? String else { return nil }
            return NewsletterEntry(
                id: postID,
                authorName: authorName,
                answer: entry["answer"] as? String ?? "",
                prompt: prompt,
                promptID: entry["promptID"] as? String ?? postID,
                imageURL: entry["imageURL"] as? String,
                createdAt: (entry["createdAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
        let winners = data["winners"] as? [String: Any]
        let mostAnswers = winners?["mostAnswers"] as? [String: Any]
        let mostPoints = winners?["mostPoints"] as? [String: Any]
        return NewsletterEdition(
            id: document.documentID,
            groupID: groupID,
            groupName: groupName,
            monthKey: monthKey,
            monthLabel: monthLabel,
            entries: entries,
            mostAnswersWinner: mostAnswers?["name"] as? String,
            mostPointsWinner: mostPoints?["name"] as? String
        )
    }

    private static func points(for answerRank: Int) -> Int {
        switch answerRank {
        case 1: return 5
        case 2: return 3
        case 3: return 2
        default: return 1
        }
    }

    private func ensureInviteRecords(from documents: [QueryDocumentSnapshot], userID: String) {
        for document in documents where document.data()["ownerID"] as? String == userID {
            let code = document.data()["inviteCode"] as? String ?? Self.inviteCode(for: document.documentID)
            Task {
                do {
                    if document.data()["inviteCode"] == nil {
                        try await document.reference.updateData(["inviteCode": code])
                    }
                    let inviteReference = database.collection("groupInvites").document(code)
                    let invite = try await inviteReference.getDocument()
                    if !invite.exists {
                        try await inviteReference.setData([
                            "groupID": document.documentID,
                            "ownerID": userID,
                            "createdAt": FieldValue.serverTimestamp()
                        ])
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func makeInviteCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
    }

    private static func inviteCode(for documentID: String) -> String {
        let characters = documentID.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(characters.prefix(6)).padding(toLength: 6, withPad: "X", startingAt: 0)
    }
}


struct AchievementTier: Equatable {
    let title: String
    let threshold: Int
    let icon: String
}

struct AchievementProgress: Identifiable {
    let id: String
    let value: Int
    let unit: String
    let tiers: [AchievementTier]
    var earnedIndex: Int? { tiers.indices.last { value >= tiers[$0].threshold } }
    var earned: AchievementTier? { earnedIndex.map { tiers[$0] } }
    var next: AchievementTier? { tiers.first { value < $0.threshold } }

    static func calculate(posts: [BlurbPost], userID: String, groupID: String) -> [Self] {
        let answers = posts.filter { !$0.isSample && $0.authorID == userID && $0.groupID == groupID }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let days = Set(answers.filter(\.countsTowardStreak).map {
            calendar.startOfDay(for: $0.createdAt.addingTimeInterval(-5 * 3600))
        }).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            run = previous.flatMap { calendar.dateComponents([.day], from: $0, to: day).day } == 1 ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        let correct = Set(answers.filter {
            let trivia = QuestionBank.weeklyTrivia(for: $0.createdAt)
            return $0.editCount == 0 && $0.promptID == trivia.id && trivia.isCorrect($0.answer)
        }.map(\.promptID)).count
        return [
            Self(id: "streak", value: longest, unit: "consecutive days", tiers: [
                .init(title: "On a Roll", threshold: 3, icon: "flame.fill"),
                .init(title: "On Fire", threshold: 7, icon: "flame.fill"),
                .init(title: "Unstoppable", threshold: 14, icon: "bolt.fill"),
                .init(title: "Daily Legend", threshold: 30, icon: "crown.fill"),
                .init(title: "Supernova", threshold: 100, icon: "sparkles")]),
            Self(id: "trivia", value: correct, unit: "correct trivia answers", tiers: [
                .init(title: "Trivia Star", threshold: 3, icon: "star"),
                .init(title: "Trivia Ace", threshold: 5, icon: "star.fill"),
                .init(title: "Trivia Master", threshold: 10, icon: "brain.head.profile"),
                .init(title: "Trivia Genius", threshold: 20, icon: "crown.fill"),
                .init(title: "Trivia Legend", threshold: 50, icon: "sparkles")]),
            Self(id: "sharing", value: Set(answers.map(\.promptID)).count, unit: "group answers", tiers: [
                .init(title: "Group Regular", threshold: 10, icon: "person.3"),
                .init(title: "Group Favorite", threshold: 25, icon: "person.3.fill"),
                .init(title: "Group Pillar", threshold: 50, icon: "hands.clap.fill"),
                .init(title: "Group Legend", threshold: 100, icon: "crown.fill"),
                .init(title: "Group Icon", threshold: 250, icon: "sparkles")])
        ]
    }
}


struct GroupMemberProfile: Identifiable {
    let id: String
    let name: String
    let photoURL: String?
}
