import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

struct BlurbGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let ownerID: String
    let memberIDs: [String]

    var memberCount: Int { memberIDs.count }
}

struct BlurbPost: Identifiable, Hashable {
    let id: String
    let entryID: String
    let groupID: String
    let authorID: String
    let authorName: String
    let authorPhotoURL: String?
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

    var likeCount: Int { likeIDs.count }
    var commentCount: Int { 0 }
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
    @Published private(set) var posts: [BlurbPost] = []
    @Published private(set) var profile = BlurbProfile()
    @Published var selectedGroupID: String?
    @Published var errorMessage: String?

    private let database = Firestore.firestore()
    private var groupsListener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var currentUserID: String?
    private var didAttemptSampleSeed = false

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

    func hasAnswered(promptID: String) -> Bool {
        guard let userID = currentUserID else { return false }
        return posts.contains { $0.authorID == userID && $0.promptID == promptID }
    }

    func answer(for promptID: String) -> BlurbPost? {
        guard let userID = currentUserID else { return nil }
        return posts.first { $0.authorID == userID && $0.promptID == promptID }
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

        groupsListener = database.collection("groups")
            .whereField("memberIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                let groups = snapshot?.documents.compactMap(Self.makeGroup) ?? []
                Task { @MainActor in
                    self.groups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if self.selectedGroupID == nil || !groups.contains(where: { $0.id == self.selectedGroupID }) {
                        self.selectedGroupID = groups.first?.id
                    }
                    self.listenForPosts()
                    self.seedSampleGroupsIfNeeded()
                }
            }

        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data() else { return }
                Task { @MainActor in
                    self?.profile = BlurbProfile(
                        displayName: data["displayName"] as? String ?? "Blurb friend",
                        photoURL: data["photoURL"] as? String
                    )
                }
            }
    }

    func stop() {
        groupsListener?.remove(); groupsListener = nil
        postsListener?.remove(); postsListener = nil
        profileListener?.remove(); profileListener = nil
        currentUserID = nil
        didAttemptSampleSeed = false
        groups = []; posts = []; selectedGroupID = nil
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
            try await reference.setData([
                "name": name,
                "ownerID": userID,
                "memberIDs": [userID],
                "createdAt": FieldValue.serverTimestamp()
            ])
            selectedGroupID = reference.documentID
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func seedSampleGroupsIfNeeded() {
        guard groups.isEmpty, !didAttemptSampleSeed, let userID = currentUserID else { return }
        didAttemptSampleSeed = true

        let samples = ["Sunday Dinner", "After Hours", "Music Swap"]
        let batch = database.batch()
        for (index, name) in samples.enumerated() {
            let reference = database.collection("groups").document("sample-\(userID)-\(index)")
            batch.setData([
                "name": name,
                "ownerID": userID,
                "memberIDs": [userID],
                "isSample": true,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: reference, merge: true)
        }

        Task {
            do {
                try await batch.commit()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createPost(answer: String, prompt: DailyPrompt) async -> Bool {
        guard let userID = currentUserID, let group = selectedGroup else {
            errorMessage = "Create a group before posting."
            return false
        }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return false }
        do {
            let entryID = UUID().uuidString
            let answerRank = posts.filter { $0.promptID == prompt.id }.count + 1
            let pointsAwarded = Self.points(for: answerRank)
            var sharedValues: [String: Any] = [
                "entryID": entryID,
                "authorID": userID,
                "authorName": profile.displayName,
                "answer": trimmedAnswer,
                "prompt": prompt.question,
                "promptID": prompt.id,
                "createdAt": FieldValue.serverTimestamp(),
                "editCount": 0,
                "countsTowardStreak": true,
                "likeIDs": [],
                "answerRank": answerRank,
                "pointsAwarded": pointsAwarded
            ]
            if let photoURL = profile.photoURL { sharedValues["authorPhotoURL"] = photoURL }

            sharedValues["groupID"] = group.id
            let reference = database.collection("posts").document("\(entryID)_\(group.id)")
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

            if post.entryID == post.id {
                try await database.collection("posts").document(post.id).updateData(changes)
            } else {
                let batch = database.batch()
                for group in groups {
                    let reference = database.collection("posts").document("\(post.entryID)_\(group.id)")
                    batch.updateData(changes, forDocument: reference)
                }
                try await batch.commit()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost(_ post: BlurbPost) async {
        guard let userID = currentUserID, post.authorID == userID else { return }
        do {
            if post.entryID == post.id {
                try await database.collection("posts").document(post.id).delete()
            } else {
                let batch = database.batch()
                for group in groups {
                    let reference = database.collection("posts").document("\(post.entryID)_\(group.id)")
                    batch.deleteDocument(reference)
                }
                try await batch.commit()
            }
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
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func listenForPosts() {
        postsListener?.remove()
        guard let groupID = selectedGroupID else { posts = []; return }
        postsListener = database.collection("posts")
            .whereField("groupID", isEqualTo: groupID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                let posts = (snapshot?.documents.compactMap(Self.makePost) ?? [])
                    .sorted { $0.createdAt > $1.createdAt }
                Task { @MainActor in self.posts = posts }
            }
    }

    private static func makeGroup(_ document: QueryDocumentSnapshot) -> BlurbGroup? {
        let data = document.data()
        guard let name = data["name"] as? String,
              let ownerID = data["ownerID"] as? String,
              let memberIDs = data["memberIDs"] as? [String] else { return nil }
        return BlurbGroup(id: document.documentID, name: name, ownerID: ownerID, memberIDs: memberIDs)
    }

    private static func makePost(_ document: QueryDocumentSnapshot) -> BlurbPost? {
        let data = document.data()
        guard let groupID = data["groupID"] as? String,
              let authorID = data["authorID"] as? String,
              let authorName = data["authorName"] as? String,
              let answer = data["answer"] as? String,
              let prompt = data["prompt"] as? String else { return nil }
        return BlurbPost(
            id: document.documentID,
            entryID: data["entryID"] as? String ?? document.documentID,
            groupID: groupID,
            authorID: authorID,
            authorName: authorName,
            authorPhotoURL: data["authorPhotoURL"] as? String,
            answer: answer,
            prompt: prompt,
            promptID: data["promptID"] as? String ?? "legacy-\(document.documentID)",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            editedAt: (data["editedAt"] as? Timestamp)?.dateValue(),
            editCount: data["editCount"] as? Int ?? 0,
            countsTowardStreak: data["countsTowardStreak"] as? Bool ?? true,
            likeIDs: data["likeIDs"] as? [String] ?? [],
            answerRank: data["answerRank"] as? Int ?? 1,
            pointsAwarded: data["pointsAwarded"] as? Int ?? 1
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
}
