import Foundation
import Security

public struct KeychainSessionHintStore: SessionHintStore, Sendable {
    public static let account = "observer-reauthentication-hint"
    private static let marker = "reauthentication-needed"

    private let service: String

    public init(service: String = "app.fluke.session-hint") {
        self.service = service
    }

    public func hasReauthenticationHint() async throws -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw SessionHintStoreError.unavailable(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              value == Self.marker else {
            throw SessionHintStoreError.malformedData
        }
        return true
    }

    public func saveReauthenticationHint() async throws {
        let data = Data(Self.marker.utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SessionHintStoreError.unavailable(updateStatus)
        }
        let query: [CFString: Any] = baseQuery.merging([
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, newValue in newValue }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SessionHintStoreError.unavailable(addStatus)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionHintStoreError.unavailable(status)
        }
    }

    public func removeSynchronouslyForTesting() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionHintStoreError.unavailable(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.account,
        ]
    }

    private var readQuery: [CFString: Any] {
        baseQuery.merging([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]) { _, newValue in newValue }
    }
}
