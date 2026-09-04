import Foundation
import Synchronization

/// Ordered delivery while healthy. Overflow terminates the entire projection,
/// with a final failure event, rather than silently continuing after a gap.
final class SessionEventBuffer<Event: Sendable>: Sendable {
    let stream: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let finished = Mutex(false)
    private let overflowEvent: Event
    private let onOverflow: @Sendable () -> Void

    init(
        capacity: Int = 500,
        overflowEvent: Event,
        onOverflow: @escaping @Sendable () -> Void = {}
    ) {
        let pair = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(max(1, capacity)))
        stream = pair.stream
        continuation = pair.continuation
        self.overflowEvent = overflowEvent
        self.onOverflow = onOverflow
    }

    func yield(_ event: Event) {
        let overflowed = finished.withLock { finished in
            guard !finished else { return false }
            switch continuation.yield(event) {
            case .dropped:
                finished = true
                continuation.yield(overflowEvent)
                continuation.finish()
                return true
            case .terminated:
                finished = true
            case .enqueued:
                break
            @unknown default:
                finished = true
                continuation.yield(overflowEvent)
                continuation.finish()
                return true
            }
            return false
        }
        if overflowed { onOverflow() }
    }

    func finish() {
        finished.withLock { finished in
            finished = true
            continuation.finish()
        }
    }
}
