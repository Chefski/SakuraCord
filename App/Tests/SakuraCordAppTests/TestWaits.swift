import Observation

/// Awaits `condition` over `@Observable` state, re-evaluating it on each
/// observed change; fails after 10 seconds.
@MainActor
func until(_ condition: @escaping @MainActor @Sendable () -> Bool) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask { await firstObservation(where: condition) }
        group.addTask {
            try? await Task.sleep(for: .seconds(10))
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
/// 10 seconds.
func eventually(
    isolation _: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(10)
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
