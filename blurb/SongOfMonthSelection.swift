import Foundation

struct SongOfMonthSelection: Identifiable, Hashable {
    let id: String
    let groupID: String
    let monthKey: String
    let userID: String
    let title: String
    let artist: String
    let authorName: String
    let createdAt: Date
    let updatedAt: Date

    var displayText: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }
}
