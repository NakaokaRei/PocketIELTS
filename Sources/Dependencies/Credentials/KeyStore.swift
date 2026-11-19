import Foundation
import Security

enum KeyStore {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.pocketielts.study.openai",
         kSecAttrAccount as String: account]
    }

    static func read(account: String) throws -> String? {
        var search = query(account)
        search[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ key: String, account: String) throws {
        let fields = [kSecValueData as String: Data(key.utf8),
                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query(account) as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query(account).merging(fields) { _, new in new } as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw StudyError.message(String(localized: "キーチェーンにアクセスできません。iPhoneのロックを解除して再試行してください。"))
        }
    }
}
