public protocol SessionHintStore: Sendable {
    func hasReauthenticationHint() async throws -> Bool
    func saveReauthenticationHint() async throws
    func clear() async throws
}

public enum SessionHintStoreError: Error, Equatable, Sendable {
    case malformedData
    case unavailable(Int32)
}
