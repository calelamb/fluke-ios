import FlukeKit
import Foundation

public protocol AuthServiceProtocol: Sendable {
    func signIn(credential: AppleCredential) async throws -> AuthenticatedUser
    func currentUser() async throws -> AuthenticatedUser
    func signOut() async throws
    func deleteAccount() async throws
}

public struct AuthService: AuthServiceProtocol, Sendable {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func signIn(credential: AppleCredential) async throws -> AuthenticatedUser {
        guard let token = String(data: credential.identityToken, encoding: .utf8),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthServiceError.invalidAppleCredential
        }
        let name = credential.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await api.post(
            APIRequest(path: ReleaseBEndpoint.authApple),
            body: AppleSignInRequest(
                identityToken: token,
                fullName: name?.isEmpty == false ? name : nil
            )
        )
    }

    public func currentUser() async throws -> AuthenticatedUser {
        try await api.get(APIRequest(path: ReleaseBEndpoint.authMe))
    }

    public func signOut() async throws {
        try await api.postNoContent(
            APIRequest(path: ReleaseBEndpoint.authLogout),
            body: EmptyRequest()
        )
        api.clearCookies()
    }

    public func deleteAccount() async throws {
        try await api.deleteNoContent(APIRequest(path: ReleaseBEndpoint.authAccount))
        api.clearCookies()
    }
}
