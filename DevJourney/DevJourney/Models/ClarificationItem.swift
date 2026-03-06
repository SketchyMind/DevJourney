import Foundation
import SwiftData

@Model
final class ClarificationItem {
    @Attribute(.unique) var id: String
    var ticketId: String
    var stage: String
    var question: String
    var answer: String?
    var answeredAt: Date?

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        stage: String,
        question: String
    ) {
        self.id = id
        self.ticketId = ticketId
        self.stage = stage
        self.question = question
    }

    func answer(_ response: String) {
        self.answer = response
        self.answeredAt = Date()
    }
}
