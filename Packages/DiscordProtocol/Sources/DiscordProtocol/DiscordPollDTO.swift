import Foundation
import SakuraCordModels

struct DiscordPollDTO: Decodable {
    struct Media: Decodable {
        struct Emoji: Decodable {
            var id: String?
            var name: String?
            var animated: Bool?
        }
        var text: String?
        var emoji: Emoji?
    }
    struct Answer: Decodable {
        var answerID: Int
        var pollMedia: Media
        enum CodingKeys: String, CodingKey {
            case answerID = "answer_id"
            case pollMedia = "poll_media"
        }
    }
    struct Count: Decodable {
        var id: Int
        var count: Int
        var meVoted: Bool?
        enum CodingKeys: String, CodingKey {
            case id, count
            case meVoted = "me_voted"
        }
    }
    struct Results: Decodable {
        var isFinalized: Bool
        var answerCounts: [Count]
        enum CodingKeys: String, CodingKey {
            case isFinalized = "is_finalized"
            case answerCounts = "answer_counts"
        }
    }
    var question: Media
    var answers: [Answer]
    var expiry: String?
    var allowMultiselect: Bool?
    var layoutType: Int?
    var results: Results?
    enum CodingKeys: String, CodingKey {
        case question, answers, expiry, results
        case allowMultiselect = "allow_multiselect"
        case layoutType = "layout_type"
    }

    var domain: MessagePoll {
        MessagePoll(
            question: question.text ?? "",
            answers: answers.map { answer in
                PollAnswer(id: answer.answerID, text: answer.pollMedia.text ?? "", emoji: answer.pollMedia.emoji.map {
                    EmojiReference(id: $0.id, name: $0.name ?? "emoji", isAnimated: $0.animated ?? false)
                })
            },
            expiry: expiry.flatMap(DiscordDate.parse),
            allowsMultipleAnswers: allowMultiselect ?? false,
            layoutType: layoutType ?? 1,
            results: results.map {
                PollResults(isFinalized: $0.isFinalized, answerCounts: $0.answerCounts.map {
                    PollAnswerCount(id: $0.id, count: $0.count, meVoted: $0.meVoted ?? false)
                })
            }
        )
    }
}

struct DiscordPollVoteDTO: Decodable {
    var channelID: String
    var messageID: String
    var userID: String
    var answerID: Int
    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case messageID = "message_id"
        case userID = "user_id"
        case answerID = "answer_id"
    }
}

extension PollDraft {
    var requestPayload: JSONValue {
        .object([
            "question": .object(["text": .string(question.trimmingCharacters(in: .whitespacesAndNewlines))]),
            "answers": .array(submittedAnswers.map { answer in
                var media: [String: JSONValue] = ["text": .string(answer.text.trimmingCharacters(in: .whitespacesAndNewlines))]
                if let emoji = answer.emoji {
                    media["emoji"] = .object(emoji.id.map { ["id": .string($0), "name": .string("")] }
                        ?? ["name": .string(emoji.name)])
                }
                return .object(["poll_media": .object(media)])
            }),
            "duration": .number(Double(durationHours)),
            "allow_multiselect": .bool(allowsMultipleAnswers),
            "layout_type": .number(1),
        ])
    }
}

struct DiscordPollVoteBatchDTO: Decodable {
    struct Vote: Decodable {
        var answerID: Int
        var users: [String]
        enum CodingKeys: String, CodingKey {
            case users
            case answerID = "answer_id"
        }
    }
    var channelID: String
    var messageID: String
    var votes: [Vote]
    enum CodingKeys: String, CodingKey {
        case votes
        case channelID = "channel_id"
        case messageID = "message_id"
    }
}
