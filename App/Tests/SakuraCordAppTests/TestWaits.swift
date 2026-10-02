import Observation

/// Hosted runners can starve the main actor for longer than ten seconds while
/// the suite runs in parallel, so waits allow a minute before failing.
private let waitDeadline: Duration = .seconds(60)

/// Awaits `condition` over `@Observable` state, re-evaluating it on each
/// observed change; fails after `waitDeadline`.
@MainActor
func until(_ condition: @escaping @MainActor @Sendable () -> Bool) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask { await firstObservation(where: condition) }
        group.addTask {
            try? await Task.sleep(for: waitDeadline)
            return false
        }
        let satisfied = await group.next() ?? false
        group.cancelAll()
        return satisfied
    }
}

@MainActor
private func firstObservation(
    where condition: @escaping @MainActor @Sendable () -> Bool
) async -> Bool {
    for await satisfied in Observations(condition) where satisfied {
        return true
    }
    return false
}

/// Polls `condition` in the caller's isolation until it holds. The fallback
/// for state that emits no signal, such as actor-isolated state; fails after
/// `waitDeadline`.
func eventually(
    isolation _: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + waitDeadline
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        guard (try? await Task.sleep(for: .milliseconds(1))) != nil else {
            break
        }
    }
    return await condition()
}

/// Awaits `task`, forwarding the caller's cancellation (such as a `.timeLimit`
/// expiry) so an unstructured child cannot keep a cancelled test waiting.
func cancellableValue<Success: Sendable>(of task: Task<Success, Never>) async -> Success {
    await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

/// Awaits `task`, forwarding the caller's cancellation to it.
func cancellableValue<Success: Sendable>(
    of task: Task<Success, any Error>
) async throws -> Success {
    try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}
