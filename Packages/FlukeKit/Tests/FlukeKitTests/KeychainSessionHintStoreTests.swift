import Foundation
import Security
import Testing

@testable import FlukeReleaseB

struct KeychainSessionHintStoreTests {
    @Test("A saved hint round trips without account or token material")
    func roundTrip() async throws {
        let service = "test.fluke.session-hint.\(UUID().uuidString)"
        let store = KeychainSessionHintStore(service: service)
        defer { try? store.removeSynchronouslyForTesting() }

        try await store.saveReauthenticationHint()

        #expect(try await store.hasReauthenticationHint())
        let raw = try read(service: service)
        #expect(String(data: raw, encoding: .utf8) == "reauthentication-needed")
    }

    @Test("Blank and malformed Keychain values fail closed")
    func malformedValues() async throws {
        for data in [Data(), Data("   \n".utf8), Data([0xff, 0xfe])] {
            let service = "test.fluke.session-hint.\(UUID().uuidString)"
            try write(data, service: service)
            let store = KeychainSessionHintStore(service: service)
            defer { try? store.removeSynchronouslyForTesting() }

            await #expect(throws: SessionHintStoreError.malformedData) {
                try await store.hasReauthenticationHint()
            }
        }
    }

    private func write(_ data: Data, service: String) throws {
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: KeychainSessionHintStore.account,
            kSecValueData: data,
        ] as CFDictionary, nil)
        #expect(status == errSecSuccess)
    }

    private func read(service: String) throws -> Data {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: KeychainSessionHintStore.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        #expect(status == errSecSuccess)
        return try #require(item as? Data)
    }
}
