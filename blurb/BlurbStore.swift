import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

struct BlurbGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let ownerID: String
    let memberIDs: [String]
    let inviteCode: String

    var memberCount: Int { memberIDs.count }
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
    let createdAt: Date
    let editedAt: Date?
    let editCount: Int
    let countsTowardStreak: Bool
    let likeIDs: [String]
    let answerRank: Int
    let pointsAwarded: Int
    let commentCount: Int

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
}

struct MonthlyWinner {
    let title: String
    let points: Int
}

struct BlurbProfile {
    var displayName: String = "Blurb friend"
    var photoURL: String?
}

@MainActor
final class BlurbStore: ObservableObject {
    @Published private(set) var groups: [BlurbGroup] = []
    @Published private(set) var groupsLoaded = false
    @Published private(set) var posts: [BlurbPost] = []
    @Published private(set) var answerCountsByGroup: [String: Int] = [:]
    @Published private(set) var profile = BlurbProfile()
    @Published private(set) var commentsByPostID: [String: [BlurbComment]] = [:]
    @Published var selectedGroupID: String?
    @Published var errorMessage: String?
    @Published private(set) var listenerErrorMessage: String?

    private let database = Firestore.firestore()
    private var groupsListener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var answerCountListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var currentUserID: String?
    private var activeAnswerCountPromptID: String?
    private var listenerGeneration = 0
    private var listenerErrors: [String: String] = [:]
#if DEBUG
    private var isAppStoreScreenshotFixture = false
#endif

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
            $0.authorID == userID && $0.promptID == promptID && $0.groupID == targetGroupID
        }
    }

    func answer(for promptID: String, in groupID: String? = nil) -> BlurbPost? {
        guard let userID = currentUserID else { return nil }
        let targetGroupID = groupID ?? selectedGroupID
        return posts.first {
            $0.authorID == userID && $0.promptID == promptID && $0.groupID == targetGroupID
        }
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
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, self.listenerGeneration == generation else { return }
                guard let data = snapshot?.data() else { return }
                Task { @MainActor in
                    guard self.listenerGeneration == generation else { return }
                    self.profile = BlurbProfile(
                        displayName: data["displayName"] as? String ?? "Blurb friend",
                        photoURL: data["photoURL"] as? String
                    )
                }
            }
    }

    func invalidateListeners() {
        listenerGeneration += 1
        currentUserID = nil
        groupsListener?.remove(); groupsListener = nil
        postsListener?.remove(); postsListener = nil
        profileListener?.remove(); profileListener = nil
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
        groups = []; groupsLoaded = false; posts = []; answerCountsByGroup = [:]; commentsByPostID = [:]; selectedGroupID = nil
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
                    let uniqueAuthors = Set(snapshot?.documents.compactMap {
                        $0.data()["authorID"] as? String
                    } ?? [])
                    Task { @MainActor in
                        guard self.listenerGeneration == generation else { return }
                        self.clearListenerError(source: "answer-count-\(group.id)")
                        self.answerCountsByGroup[group.id] = uniqueAuthors.count
                    }
                }
        }
    }

    func answerCount(in groupID: String) -> Int {
        answerCountsByGroup[groupID, default: 0]
    }

    func currentAnswerRank(for post: BlurbPost) -> Int {
        let rankedPosts = posts
            .filter { $0.groupID == post.groupID && $0.promptID == post.promptID }
            .sorted {
                if $0.effectivePostedAt == $1.effectivePostedAt { return $0.id < $1.id }
                return $0.effectivePostedAt < $1.effectivePostedAt
            }
        return rankedPosts.firstIndex(where: { $0.id == post.id }).map { $0 + 1 } ?? post.answerRank
    }

    func select(_ group: BlurbGroup) {
        selectedGroupID = group.id
        listenForPosts()
    }

    func createGroup(named rawName: String) async -> Bool {
        guard let userID = currentUserID else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            let reference = database.collection("groups").document()
            let inviteCode = Self.makeInviteCode()
            let batch = database.batch()
            batch.setData([
                "name": name,
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
                inviteCode: inviteCode
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
            let answerRank = posts.filter { $0.promptID == prompt.id && $0.groupID == targetGroupID }.count + 1
            let pointsAwarded = Self.points(for: answerRank)
            var sharedValues: [String: Any] = [
                "entryID": entryID,
                "authorID": userID,
                "authorName": profile.displayName,
                "answer": trimmedAnswer,
                "prompt": prompt.question,
                "promptID": prompt.id,
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
        guard post.editCount == 0 else {
            errorMessage = "Each Blurb can only be edited once."
            return false
        }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return false }
        do {
            let changes: [String: Any] = [
                "answer": trimmedAnswer,
                "editedAt": FieldValue.serverTimestamp(),
                "editCount": 1,
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
            var values: [String: Any] = ["displayName": name, "lastSeenAt": FieldValue.serverTimestamp()]
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
                for post in authoredPosts.documents {
                    try await post.reference.updateData(postProfileValues)
                }
            }

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
            BlurbPost(id: "post-alex", entryID: "post-alex", groupID: group.id, authorID: userID, authorName: "Alex", authorPhotoURL: nil, imageURL: nil, answer: "A quiet cup of coffee before everyone woke up.", prompt: prompt.question, promptID: prompt.id, createdAt: now.addingTimeInterval(-300), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: ["maya", "jordan"], answerRank: 1, pointsAwarded: 3, commentCount: 2),
            BlurbPost(id: "post-maya", entryID: "post-maya", groupID: group.id, authorID: "maya", authorName: "Maya", authorPhotoURL: nil, imageURL: nil, answer: "The coffee shop remembered my order ☕️", prompt: prompt.question, promptID: prompt.id, createdAt: now.addingTimeInterval(-240), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: [userID, "sam"], answerRank: 2, pointsAwarded: 2, commentCount: 1),
            BlurbPost(id: "post-jordan", entryID: "post-jordan", groupID: group.id, authorID: "jordan", authorName: "Jordan", authorPhotoURL: nil, imageURL: nil, answer: "Ten minutes of sunshine between meetings.", prompt: prompt.question, promptID: prompt.id, createdAt: now.addingTimeInterval(-180), editedAt: nil, editCount: 0, countsTowardStreak: true, likeIDs: ["maya"], answerRank: 3, pointsAwarded: 1, commentCount: 0)
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
            inviteCode: data["inviteCode"] as? String ?? inviteCode(for: document.documentID)
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
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
            editCount: data["editCount"] as? Int ?? 0,
            countsTowardStreak: data["countsTowardStreak"] as? Bool ?? true,
            likeIDs: data["likeIDs"] as? [String] ?? [],
            answerRank: data["answerRank"] as? Int ?? 1,
            pointsAwarded: data["pointsAwarded"] as? Int ?? 1,
            commentCount: data["commentCount"] as? Int ?? 0
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
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now
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
