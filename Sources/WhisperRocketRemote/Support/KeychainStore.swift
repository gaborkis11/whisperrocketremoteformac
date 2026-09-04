import Foundation
import Security

nonisolated enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)

    var message: String {
        switch self {
        case .unexpectedStatus(let status):
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(text)"
        }
    }
}

/// The host token, in the login keychain as a generic password.
///
/// Only the token lives here — everything else is UserDefaults. The stable
/// signing identity is what keeps macOS from re-asking for keychain access
/// after every rebuild, so the service/account pair must never change.
nonisolated struct KeychainStore: Sendable {
    static let defaultService = "com.gaborkis.WhisperRocketRemote"
    static let tokenAccount = "host-token"

    let service: String
    let account: String

    init(service: String = defaultService, account: String = tokenAccount) {
        self.service = service
        self.account = account
    }

    /// `nil` when nothing has been stored yet — not an error.
    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Storing an empty token deletes the item: "no token" has exactly one
    /// representation, so nothing downstream has to handle `Optional("")`.
    func write(_ token: String) throws {
        guard !token.isEmpty else {
            try delete()
            return
        }
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            // The token is needed by a login item that may start before the
            // user unlocks the screen, but never while the machine is locked.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let add = SecItemAdd(query as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError.unexpectedStatus(add) }
        default:
            throw KeychainError.unexpectedStatus(update)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Where the host token comes from: the keychain in the app, a literal in the
/// `--flow-probe` harness, so a probe run can never rewrite the real token.
nonisolated struct TokenSource: Sendable {
    let read: @Sendable () -> String

    static func keychain(_ store: KeychainStore = KeychainStore()) -> TokenSource {
        TokenSource { (try? store.read()) ?? nil ?? "" }
    }

    static func literal(_ token: String) -> TokenSource {
        TokenSource { token }
    }
}
