import Foundation

func withTaskDeadline<Value: Sendable>(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let pair = AsyncThrowingStream<Value, Error>.makeStream()
    let operationTask = Task {
        do {
            let value = try await operation()
            pair.continuation.yield(value)
            pair.continuation.finish()
        } catch {
            pair.continuation.finish(throwing: error)
        }
    }
    let timeoutTask = Task {
        do {
            try await Task.sleep(for: timeout)
            pair.continuation.finish(throwing: APIError.timeout)
        } catch {
            // The winning operation cancels this timer.
        }
    }
    var iterator = pair.stream.makeAsyncIterator()

    return try await withTaskCancellationHandler {
        defer {
            operationTask.cancel()
            timeoutTask.cancel()
        }
        guard let value = try await iterator.next() else {
            try Task.checkCancellation()
            throw APIError.transport
        }
        try Task.checkCancellation()
        return value
    } onCancel: {
        operationTask.cancel()
        timeoutTask.cancel()
        pair.continuation.finish(throwing: CancellationError())
    }
}
