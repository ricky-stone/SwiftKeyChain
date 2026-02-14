import Foundation
import Security

public enum SwiftKeyChainError: Error, LocalizedError, Equatable {
    case invalidKey
    case duplicateKey
    case keyNotFound
    case encodingFailed
    case decodingFailed
    case unexpectedData
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The key cannot be empty."
        case .duplicateKey:
            return "A value already exists for this key."
        case .keyNotFound:
            return "No value was found for this key."
        case .encodingFailed:
            return "The value could not be encoded."
        case .decodingFailed:
            return "The value could not be decoded as the requested type."
        case .unexpectedData:
            return "Keychain returned data in an unexpected format."
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

public enum KeychainAccessibility: Sendable {
    case whenUnlocked
    case afterFirstUnlock
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlockThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly

    var secValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

public struct SwiftKeyChainConfiguration: Sendable {
    public var service: String
    public var accessGroup: String?
    public var synchronizable: Bool
    public var accessibility: KeychainAccessibility

    public init(
        service: String = SwiftKeyChain.defaultService,
        accessGroup: String? = nil,
        synchronizable: Bool = true,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.accessibility = accessibility
    }
}

public final class SwiftKeyChain {
    public static var defaultService: String {
        Bundle.main.bundleIdentifier ?? "SwiftKeyChain.DefaultService"
    }

    public let configuration: SwiftKeyChainConfiguration

    public init(configuration: SwiftKeyChainConfiguration = .init()) {
        self.configuration = configuration
    }

    public convenience init(
        service: String? = nil,
        accessGroup: String? = nil,
        synchronizable: Bool = true,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) {
        self.init(
            configuration: SwiftKeyChainConfiguration(
                service: service ?? Self.defaultService,
                accessGroup: accessGroup,
                synchronizable: synchronizable,
                accessibility: accessibility
            )
        )
    }

    public func AddKey<T: Codable>(_ key: String, _ value: T) throws {
        try addKey(key, value)
    }

    public func addKey<T: Codable>(_ key: String, _ value: T) throws {
        try setValue(value, forKey: key, mode: .upsert)
    }

    public func addKey(_ key: String, _ value: Data) throws {
        try setData(value, forKey: key)
    }

    public func updateKey<T: Codable>(_ key: String, _ value: T) throws {
        try setValue(value, forKey: key, mode: .updateOnly)
    }

    public func updateKey(_ key: String, _ value: Data) throws {
        try setRawData(value, forKey: key, mode: .updateOnly)
    }

    public func setData(_ data: Data, forKey key: String) throws {
        try setRawData(data, forKey: key, mode: .upsert)
    }

    public func getKey<T: Codable>(_ key: String, as type: T.Type = T.self) throws -> T? {
        if type == Data.self {
            return try getData(forKey: key) as? T
        }

        guard let data = try getData(forKey: key) else {
            return nil
        }

        return try decode(data, as: type)
    }

    public func getModel<T: Codable>(_ key: String, as type: T.Type = T.self) throws -> T? {
        try getKey(key, as: type)
    }

    public func getKey<T: Codable>(
        _ key: String,
        default defaultValue: T,
        as type: T.Type = T.self
    ) throws -> T {
        try getKey(key, as: type) ?? defaultValue
    }

    public func getKey(_ key: String) throws -> String? {
        try getKey(key, as: String.self)
    }

    public func getKey(_ key: String, _ defaultValue: String) throws -> String {
        try getKey(key, default: defaultValue, as: String.self)
    }

    public func getInt(_ key: String) throws -> Int? {
        try getKey(key, as: Int.self)
    }

    public func getDouble(_ key: String) throws -> Double? {
        try getKey(key, as: Double.self)
    }

    public func getBool(_ key: String) throws -> Bool? {
        try getKey(key, as: Bool.self)
    }

    public func getData(forKey key: String) throws -> Data? {
        let validatedKey = try validateKey(key)
        return try readRawData(forKey: validatedKey)
    }

    public func containsKey(_ key: String) throws -> Bool {
        try getData(forKey: key) != nil
    }

    @discardableResult
    public func deleteKey(_ key: String) throws -> Bool {
        try removeKey(key)
    }

    @discardableResult
    public func removeKey(_ key: String) throws -> Bool {
        let validatedKey = try validateKey(key)
        let query = keyQuery(for: validatedKey)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw statusToError(status)
        }
    }

    public func removeAllKeys() throws {
        let keys = try allKeys()
        for key in keys {
            _ = try removeKey(key)
        }
    }

    public func removeAllAvailableKeys() throws {
        for isSynchronizable in [false, true] {
            var query = serviceQuery()
            query[kSecAttrSynchronizable as String] = isSynchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                if status == errSecMissingEntitlement && isSynchronizable {
                    continue
                }
                throw statusToError(status)
            }
        }
    }

    public func allKeys() throws -> [String] {
        try keysForQuery()
    }

    private enum WriteMode {
        case upsert
        case updateOnly
    }

    private func setValue<T: Codable>(_ value: T, forKey key: String, mode: WriteMode) throws {
        if let rawData = value as? Data {
            try setRawData(rawData, forKey: key, mode: mode)
            return
        }

        let data = try encode(value)
        try setRawData(data, forKey: key, mode: mode)
    }

    private func setRawData(_ data: Data, forKey key: String, mode: WriteMode) throws {
        let validatedKey = try validateKey(key)

        switch mode {
        case .upsert:
            do {
                try addRawData(data, forKey: validatedKey)
            } catch SwiftKeyChainError.duplicateKey {
                try updateRawData(data, forKey: validatedKey)
            }
        case .updateOnly:
            try updateRawData(data, forKey: validatedKey)
        }
    }

    private func addRawData(_ data: Data, forKey key: String) throws {
        var query = keyQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = configuration.accessibility.secValue

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw statusToError(status)
        }
    }

    private func updateRawData(_ data: Data, forKey key: String) throws {
        let searchQuery = keyQuery(for: key)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: configuration.accessibility.secValue,
        ]

        let status = SecItemUpdate(
            searchQuery as CFDictionary,
            attributesToUpdate as CFDictionary
        )
        guard status == errSecSuccess else {
            throw statusToError(status)
        }
    }

    private func readRawData(forKey key: String) throws -> Data? {
        var query = keyQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SwiftKeyChainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw statusToError(status)
        }
    }

    private func encode<T: Codable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SwiftKeyChainError.encodingFailed
        }
    }

    private func decode<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SwiftKeyChainError.decodingFailed
        }
    }

    private func validateKey(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SwiftKeyChainError.invalidKey
        }
        return trimmed
    }

    private func keyQuery(for key: String) -> [String: Any] {
        var query = serviceQuery()
        query[kSecAttrAccount as String] = key
        return query
    }

    private func serviceQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
        ]

        query[kSecAttrSynchronizable as String] =
            configuration.synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func keysForQuery() throws -> [String] {
        var query = serviceQuery()
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw statusToError(status)
        }

        if let items = result as? [[String: Any]] {
            return Array(Set(items.compactMap { $0[kSecAttrAccount as String] as? String })).sorted()
        }
        if let item = result as? [String: Any],
           let key = item[kSecAttrAccount as String] as? String {
            return [key]
        }

        throw SwiftKeyChainError.unexpectedData
    }

    private func statusToError(_ status: OSStatus) -> SwiftKeyChainError {
        switch status {
        case errSecDuplicateItem:
            return .duplicateKey
        case errSecItemNotFound:
            return .keyNotFound
        default:
            return .unhandledStatus(status)
        }
    }
}
