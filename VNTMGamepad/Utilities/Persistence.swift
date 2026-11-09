//
//  Persistence.swift
//  VNTM Gamepad
//
//  Small storage abstractions so services can be tested with an in-memory
//  store instead of UserDefaults.
//

import Foundation
import Security

protocol KeyValueStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func data(forKey defaultName: String) -> Data?
    func string(forKey defaultName: String) -> String?
    func integer(forKey defaultName: String) -> Int
    func bool(forKey defaultName: String) -> Bool
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}

final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    init() {}

    func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        if let value = value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    func removeObject(forKey defaultName: String) {
        set(nil, forKey: defaultName)
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

/// Keychain wrapper used for the optional AES passphrase.
/// Pairing data is not high-value, but it should not sit in a plist.
enum KeychainStore {
    private static let service = AppConstants.bundleIdentifier

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

/// File-backed JSON storage with atomic writes and corruption recovery.
enum DocumentStore {
    static func url(for filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("VNTMGamepad", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(filename)
    }

    static func write(_ data: Data, to filename: String) throws {
        let destination = url(for: filename)
        try data.write(to: destination, options: .atomic)
    }

    static func read(_ filename: String) -> Data? {
        try? Data(contentsOf: url(for: filename))
    }

    /// Moves a corrupt file aside so the next launch starts clean.
    static func quarantine(_ filename: String) {
        let source = url(for: filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = source.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: source, to: destination)
    }
}
