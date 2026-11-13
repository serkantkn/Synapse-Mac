//
//  PairingTokenStore.swift
//  Synapse Server
//
//  Pairing tokens live in the Keychain, not in UserDefaults (a plist any process running
//  as the user can read). Items are this-device-only, so they never sync or migrate.
//  Same implementation as Synapse iOS — keep them in sync.
//

import Foundation
import Security
import os.log

enum PairingTokenStore {
    private static let service = "com.serkantkn.synapse.pairing-token"
    private static let logger = Logger(subsystem: "com.serkantkn.synapse", category: "PairingTokenStore")

    static func get(_ deviceId: String) -> String? {
        var query = baseQuery(deviceId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecMissingEntitlement {
            query[kSecUseDataProtectionKeychain as String] = false
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound { logger.warning("Keychain read failed: \(status)") }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ token: String, for deviceId: String) -> Bool {
        remove(deviceId)
        var item = baseQuery(deviceId)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            item[kSecUseDataProtectionKeychain as String] = false
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess { logger.error("Keychain write failed: \(status)") }
        return status == errSecSuccess
    }

    /// Device ids that currently have a stored token.
    static func allDeviceIds() -> [String] {
        var ids: [String] = []
        for dataProtection in [true, false] {
            var query = baseQuery(nil)
            query[kSecUseDataProtectionKeychain as String] = dataProtection
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let items = result as? [[String: Any]] else { continue }
            ids += items.compactMap { $0[kSecAttrAccount as String] as? String }
        }
        return Array(Set(ids))
    }

    static func remove(_ deviceId: String) {
        var query = baseQuery(deviceId)
        SecItemDelete(query as CFDictionary)
        query[kSecUseDataProtectionKeychain as String] = false
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(_ deviceId: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let deviceId = deviceId { query[kSecAttrAccount as String] = deviceId }
        return query
    }
}
