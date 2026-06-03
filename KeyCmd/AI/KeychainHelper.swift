//
//  KeychainHelper.swift
//  KeyCmd
//
//  Created on 2026/2/26.
//

import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let serviceName = "com.openterface.keycmd"
    
    // MARK: - Save
    func save(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8) ?? Data()
        ]
        
        // Delete existing value if present
        SecItemDelete(query as CFDictionary)
        
        // Add new value
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            LogManager.shared.log("Keychain save failed for key '\(key)': status \(status)",
                                category: "Keychain", level: .error)
        }
    }
    
    // MARK: - Retrieve
    func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let data = result as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
        }
        
        if status != errSecItemNotFound {
            LogManager.shared.log("Keychain retrieve failed for key '\(key)': status \(status)",
                                category: "Keychain", level: .error)
        }
        
        return nil
    }
    
    // MARK: - Delete
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            LogManager.shared.log("Keychain delete failed for key '\(key)': status \(status)",
                                category: "Keychain", level: .error)
        }
    }
}
