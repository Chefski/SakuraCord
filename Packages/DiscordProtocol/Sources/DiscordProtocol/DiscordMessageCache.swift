import SakuraCordModels

/// Provider reconciliation is a bounded working set, independent of the UI's
/// conversation caches. Updates retain their place until the next insertion.
struct DiscordMessageCache {
    private struct Links {
        var previous: MessageID?
        var next: MessageID?
    }

    let capacity: Int
    private var messages: [MessageID: Message] = [:]
    private var links: [MessageID: Links] = [:]
    private var oldest: MessageID?
    private var newest: MessageID?

    init(capacity: Int = 10_000) {
        self.capacity = max(1, capacity)
    }

    var count: Int { messages.count }
    var values: Dictionary<MessageID, Message>.Values { messages.values }

    subscript(id: MessageID) -> Message? {
        get { messages[id] }
        set {
            guard let newValue else {
                remove(id)
                return
            }
            if messages[id] == nil {
                while messages.count >= capacity, let oldest { remove(oldest) }
                links[id] = Links(previous: newest)
                if let newest { links[newest]?.next = id } else { oldest = id }
                newest = id
            }
            messages[id] = newValue
        }
    }

    mutating func removeAll(where shouldRemove: (Message) -> Bool) {
        for id in messages.values.filter(shouldRemove).map(\.id) { remove(id) }
    }

    mutating func removeAll() {
        messages.removeAll()
        links.removeAll()
        oldest = nil
        newest = nil
    }

    private mutating func remove(_ id: MessageID) {
        guard let node = links.removeValue(forKey: id) else { return }
        messages[id] = nil
        if let previous = node.previous { links[previous]?.next = node.next } else { oldest = node.next }
        if let next = node.next { links[next]?.previous = node.previous } else { newest = node.previous }
    }
}
