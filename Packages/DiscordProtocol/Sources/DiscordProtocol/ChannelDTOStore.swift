/// A value-semantic channel map whose empty hash-table slots reserve only a
/// reference, rather than the full channel DTO. Immutable entries can be shared
/// by snapshots; a nested channel mutation replaces just that entry.
struct ChannelDTOStore: ExpressibleByDictionaryLiteral {
    private final class Entry {
        let value: ChannelDTO

        init(_ value: ChannelDTO) {
            self.value = value
        }
    }

    private var storage: [String: Entry]

    init(dictionaryLiteral elements: (String, ChannelDTO)...) {
        storage = Dictionary(uniqueKeysWithValues: elements.map { ($0.0, Entry($0.1)) })
    }

    init<Elements: Sequence>(
        _ elements: Elements,
        uniquingKeysWith combine: (ChannelDTO, ChannelDTO) -> ChannelDTO
    ) where Elements.Element == (String, ChannelDTO) {
        storage = Dictionary(
            elements.lazy.map { ($0.0, Entry($0.1)) },
            uniquingKeysWith: { Entry(combine($0.value, $1.value)) }
        )
    }

    subscript(key: String) -> ChannelDTO? {
        get { storage[key]?.value }
        set { storage[key] = newValue.map(Entry.init) }
    }

    var keys: some Collection<String> { storage.keys }
    var values: some Collection<ChannelDTO> { storage.values.lazy.map(\.value) }
}
