import SakuraCordModels
import SwiftUI

struct PollVotersView: View {
    let model: AppModel
    let message: Message
    @State private var selectedAnswerID: Int
    @State private var users: [User] = []
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var requestID = UUID()

    private struct LoadIdentity: Equatable {
        let answerID: Int
        let count: Int?
    }

    init(model: AppModel, message: Message, initialAnswerID: Int) {
        self.model = model
        self.message = message
        _selectedAnswerID = State(initialValue: initialAnswerID)
    }

    private var poll: MessagePoll? {
        model.messageInWorkspace(channelID: message.channelID, messageID: message.id)?.poll ?? message.poll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(poll?.question ?? "Poll voters").font(.headline).lineLimit(3)
            if let poll {
                PollChoiceControl(title: "Answer", selection: $selectedAnswerID, options: poll.answers.map { answer in
                    .init(id: answer.id, title: "\(answer.text) (\(poll.count(for: answer.id)))")
                })
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(users) { user in
                        HStack(spacing: 10) {
                            AvatarView(name: user.displayName, url: user.avatarURL, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.membersByID[user.id]?.user.displayName ?? user.displayName).font(.callout.weight(.medium))
                                Text(user.username).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    if isLoading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) } else if let error {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await load(reset: users.isEmpty) } }.buttonStyle(PollButtonStyle())
                    } else if users.isEmpty {
                        Text("No votes for this answer yet.").foregroundStyle(.secondary).padding(.vertical, 24)
                    } else if hasMore {
                        Button("Load More") { Task { await load(reset: false) } }.buttonStyle(PollButtonStyle()).frame(maxWidth: .infinity)
                    }
                }
            }
        }.padding(18).frame(width: 324, height: 374)
        .task(id: LoadIdentity(answerID: selectedAnswerID, count: poll?.results == nil ? nil : poll?.count(for: selectedAnswerID))) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        let answerID = selectedAnswerID
        let requestID = UUID()
        self.requestID = requestID
        let session = model.accountSession()
        if reset { users = []; hasMore = false }
        error = nil
        isLoading = true
        defer { if self.requestID == requestID { isLoading = false } }
        if poll?.results != nil, poll?.count(for: answerID) == 0 {
            users = []
            hasMore = false
            return
        }
        do {
            let page = try await session.provider.pollVoters(messageID: message.id, channelID: message.channelID,
                                                           answerID: answerID, after: reset ? nil : users.last?.id, limit: 100)
            guard !Task.isCancelled, self.requestID == requestID, selectedAnswerID == answerID, model.isCurrentAccountSession(session) else { return }
            var seen = Set(users.map(\.id))
            users.append(contentsOf: page.users.filter { seen.insert($0.id).inserted })
            hasMore = page.hasMore
        } catch {
            guard !Task.isCancelled, self.requestID == requestID, selectedAnswerID == answerID, model.isCurrentAccountSession(session) else { return }
            self.error = error.localizedDescription
        }
    }
}
