import Foundation

struct PhotoOfMonthSelection: Identifiable, Hashable {
    let id: String
    let groupID: String
    let monthKey: String
    let userID: String
    let postID: String
    let imageURL: String
    let authorName: String
    let postCreatedAt: Date
    let createdAt: Date
    let updatedAt: Date
}
