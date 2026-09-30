import Foundation
import Observation

@MainActor
@Observable
final class SelectionFieldModel<ID: Hashable & Sendable> {
    typealias Option = SelectionFieldOption<ID>

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case needsMoreCharacters(Int)
        case failed(String)
    }

    private var source: SelectionFieldSource<ID>
    private var optionsByID: [ID: Option]
    private var task: Task<Void, Never>?
    private var generation = 0
    private var selectedIDs: Set<ID> = []

    private(set) var query = ""
    private(set) var results: [Option]
    private(set) var state: State

    init(source: SelectionFieldSource<ID>) {
        self.source = source
        let initialOptions: [Option] = switch source {
        case .local(let options, let maximumResults):
            Self.limited(options, maximum: maximumResults)
        case .dynamic(let initialOptions, _, _, let maximumResults, _):
            Self.limited(initialOptions, maximum: maximumResults)
        }
        let retainedOptions: [Option] = switch source {
        case .local(let options, _): options
        case .dynamic(let initialOptions, _, _, _, _): initialOptions
        }
        results = initialOptions
        state = switch source {
        case .local: .loaded
        case .dynamic: .loaded
        }
        optionsByID = Dictionary(
            retainedOptions.map { ($0.id, $0) },
            uniquingKeysWith: { _, newer in newer }
        )
    }

    isolated deinit {
        task?.cancel()
    }

    func activate() {
        guard state == .idle else { return }
        schedule(query: query, immediate: true)
    }

    func updateQuery(_ value: String) {
        guard query != value else { return }
        query = value
        schedule(query: value, immediate: false)
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        if state == .loading { state = .idle }
    }

    func retry() {
        schedule(query: query, immediate: true)
    }

    func replaceSource(_ source: SelectionFieldSource<ID>) {
        self.source = source
        switch source {
        case .local(let options, _):
            for option in options { optionsByID[option.id] = option }
            schedule(query: query, immediate: true)
        case .dynamic(let options, _, _, _, _):
            for option in options { optionsByID[option.id] = option }
            if query.isEmpty { schedule(query: query, immediate: true) }
        }
    }

    func retainSelectedOptions(_ ids: [ID]) { selectedIDs = Set(ids) }

    var searchesRemotely: Bool {
        if case .dynamic = source { return true }
        return false
    }

    func option(for id: ID) -> Option? {
        optionsByID[id]
    }

    private func schedule(query: String, immediate: Bool) {
        generation &+= 1
        let requestedGeneration = generation
        task?.cancel()

        switch source {
        case .local(let options, let maximumResults):
            let normalizedQuery = Option.normalized(query)
            if normalizedQuery.isEmpty {
                install(Self.limited(options, maximum: maximumResults))
                return
            }
            if options.count <= 1_000 {
                let terms = normalizedQuery.split(whereSeparator: \.isWhitespace)
                install(Self.limited(options.filter { option in
                    terms.allSatisfy { option.searchText.contains($0) }
                }, maximum: maximumResults))
                return
            }
            results = []
            state = .loading
            task = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    Self.filtered(options, query: normalizedQuery, maximum: maximumResults)
                }
                let matches = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, !Task.isCancelled,
                      requestedGeneration == generation else { return }
                install(matches)
            }

        case let .dynamic(
            initialOptions,
            minimumQueryLength,
            debounce,
            maximumResults,
            search
        ):
            let normalizedQuery = query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if normalizedQuery.isEmpty {
                install(Self.limited(
                    initialOptions,
                    maximum: maximumResults
                ))
                return
            }
            guard normalizedQuery.count >= minimumQueryLength else {
                results = []
                state = .needsMoreCharacters(minimumQueryLength)
                return
            }
            results = []
            state = .loading
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    if !immediate, debounce > .zero {
                        try await Task.sleep(for: debounce)
                    }
                    try Task.checkCancellation()
                    let loaded = try await search(normalizedQuery)
                    try Task.checkCancellation()
                    guard requestedGeneration == generation else { return }
                    install(Self.limited(loaded, maximum: maximumResults))
                } catch is CancellationError {
                    return
                } catch {
                    guard requestedGeneration == generation else { return }
                    results = []
                    state = .failed(error.localizedDescription)
                    task = nil
                }
            }
        }
    }

    nonisolated private static func filtered(_ options: [Option], query: String, maximum: Int?) -> [Option] {
        var matches: [Option] = []
        let terms = query.split(whereSeparator: \.isWhitespace)
        for option in options {
            guard !Task.isCancelled else { return [] }
            if terms.allSatisfy({ option.searchText.contains($0) }) {
                matches.append(option)
                if let maximum, matches.count >= maximum { break }
            }
        }
        return limited(matches, maximum: maximum)
    }

    private func install(_ options: [Option]) {
        results = options
        if case .dynamic(let initial, _, _, _, _) = source {
            let retained = selectedIDs.union(initial.map(\.id))
            optionsByID = optionsByID.filter { retained.contains($0.key) }
        }
        for option in options {
            optionsByID[option.id] = option
        }
        state = .loaded
        task = nil
    }

    nonisolated private static func limited(
        _ options: [Option],
        maximum: Int?
    ) -> [Option] {
        guard let maximum else { return options }
        return Array(options.prefix(max(0, maximum)))
    }
}
