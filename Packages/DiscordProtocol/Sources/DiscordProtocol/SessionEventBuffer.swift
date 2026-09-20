import Foundation
import Synchronization

/// A single-consumer queue bounded by deliveries. A synchronous initial payload
/// may contain multiple events in one delivery; consumers still receive each
/// event in order. Overflow discards incomplete work immediately.
final class SessionEventBuffer<Event: Sendable>: Sendable {
    let stream: AsyncStream<Event>
    private let storage: Storage
    private let onOverflow: @Sendable () -> Void

    init(
        capacity: Int = 500,
        overflowEvent: Event,
        coalescing: @escaping @Sendable (Event, Event) -> Event? = { _, _ in nil },
        onOverflow: @escaping @Sendable () -> Void = {}
    ) {
        let storage = Storage(capacity: max(1, capacity), overflowEvent: overflowEvent, coalescing: coalescing)
        self.storage = storage
        self.onOverflow = onOverflow
        stream = AsyncStream(unfolding: { await storage.next() }, onCancel: { storage.cancel() })
    }

    func yield(_ event: Event) {
        if storage.yield(event) { onOverflow() }
    }

    /// Only the serial producer may batch, and it must not suspend between
    /// beginBatch and endBatch. This bounds batching to one decoded payload.
    func beginBatch() { storage.beginBatch() }
    func endBatch() {
        if storage.endBatch() { onOverflow() }
    }

    func finish() { storage.finish() }
    deinit { storage.finish() }

    private final class Storage: Sendable {
        private struct Delivery {
            var events: [Event]
            var index = 0
        }

        private struct State {
            var deliveries: [Delivery?]
            var head = 0
            var count = 0
            var batch: [Event]?
            var finished = false
            var waiter: CheckedContinuation<Event?, Never>?
        }

        private struct Enqueued {
            var overflowed = false
            var waiter: CheckedContinuation<Event?, Never>?
            var event: Event?

            func resume() { waiter?.resume(returning: event) }
        }

        private let state: Mutex<State>
        private let overflowEvent: Event
        private let coalescing: @Sendable (Event, Event) -> Event?

        init(capacity: Int, overflowEvent: Event, coalescing: @escaping @Sendable (Event, Event) -> Event?) {
            state = Mutex(State(deliveries: Array(repeating: nil, count: capacity)))
            self.overflowEvent = overflowEvent
            self.coalescing = coalescing
        }

        func yield(_ event: Event) -> Bool {
            let result = state.withLock { state in
                guard !state.finished else { return Enqueued() }
                if state.batch != nil {
                    state.batch?.append(event)
                    return Enqueued()
                }
                return enqueue([event], into: &state)
            }
            // Resuming under the mutex can invert Swift's task-status lock
            // against onCancel. All continuation resumes stay outside it.
            result.resume()
            return result.overflowed
        }

        func beginBatch() {
            state.withLock { state in
                precondition(state.batch == nil, "Event batches must not overlap")
                if !state.finished { state.batch = [] }
            }
        }

        func endBatch() -> Bool {
            let result = state.withLock { state in
                let events = state.batch ?? []
                state.batch = nil
                guard !state.finished, !events.isEmpty else { return Enqueued() }
                return enqueue(events, into: &state)
            }
            result.resume()
            return result.overflowed
        }

        private func enqueue(_ events: [Event], into state: inout State) -> Enqueued {
            var result = Enqueued()
            var delivery = Delivery(events: events)
            if let waiter = state.waiter {
                state.waiter = nil
                result.waiter = waiter
                result.event = events[0]
                delivery.index = 1
                if events.count == 1 { return result }
            }
            if state.count > 0, events.count == 1 {
                let tail = (state.head + state.count - 1) % state.deliveries.count
                if let previous = state.deliveries[tail], previous.events.count == 1,
                   let merged = coalescing(previous.events[0], events[0]) {
                    state.deliveries[tail] = Delivery(events: [merged])
                    return result
                }
            }
            guard state.count < state.deliveries.count else {
                state.deliveries = Array(repeating: nil, count: state.deliveries.count)
                state.head = 0
                state.count = 1
                state.deliveries[0] = Delivery(events: [overflowEvent])
                state.finished = true
                result.overflowed = true
                return result
            }
            state.deliveries[(state.head + state.count) % state.deliveries.count] = delivery
            state.count += 1
            return result
        }

        func next() async -> Event? {
            await withCheckedContinuation { continuation in
                let result: (ready: Bool, event: Event?) = state.withLock { state in
                    if var delivery = state.deliveries[state.head], state.count > 0 {
                        let event = delivery.events[delivery.index]
                        delivery.index += 1
                        if delivery.index == delivery.events.count {
                            state.deliveries[state.head] = nil
                            state.head = (state.head + 1) % state.deliveries.count
                            state.count -= 1
                        } else {
                            state.deliveries[state.head] = delivery
                        }
                        return (true, event)
                    }
                    if state.finished { return (true, nil) }
                    state.waiter = continuation
                    return (false, nil)
                }
                if result.ready { continuation.resume(returning: result.event) }
            }
        }

        func finish() {
            let waiter = state.withLock { state in
                state.finished = true
                state.batch = nil
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(returning: nil)
        }

        func cancel() {
            let waiter = state.withLock { state in
                state.finished = true
                state.batch = nil
                state.deliveries = Array(repeating: nil, count: state.deliveries.count)
                state.count = 0
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(returning: nil)
        }
    }
}
