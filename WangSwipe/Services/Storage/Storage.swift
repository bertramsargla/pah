import Foundation
import Security
import UIKit

/// Keeps the user's photo on device, in Application Support.
struct PhotoStore {
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    private var fileURL: URL { directory.appendingPathComponent("user-photo.jpg") }

    func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func save(_ image: UIImage) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Small wrapper for storing secrets such as an API key in the Keychain.
enum KeychainStore {
    private static let service = "com.wangswipe.app"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(match as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = match
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
