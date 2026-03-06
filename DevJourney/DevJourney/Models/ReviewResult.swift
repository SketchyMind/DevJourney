import Foundation
import SwiftData

@Model
final class ReviewResult {
    @Attribute(.unique) var id: String
    var ticketId: String
    var stage: String
    var approved: Bool
    var reviewerComment: String?
    var approvedAt: Date?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        stage: String,
        approved: Bool = false
    ) {
        self.id = id
        self.ticketId = ticketId
        self.stage = stage
        self.approved = approved
        self.approvedAt = approved ? Date() : nil
        self.createdAt = Date()
    }

    func setComment(_ comment: String) {
        self.reviewerComment = comment
    }
}
