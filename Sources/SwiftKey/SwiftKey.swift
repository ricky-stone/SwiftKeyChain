import Foundation
import Security

public enum SwiftKeyError: Error, LocalizedError, Equatable {
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

public struct SwiftKeyConfiguration: Sendable {
    public var service: String
    public var accessGroup: String?
    public var synchronizable: Bool
    public var accessibility: KeychainAccessibility

    public init(
        service: String = SwiftKey.defaultService,
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

public final class SwiftKey {
    private static let syncFallbackStatuses: Set<OSStatus> = [
        errSecMissingEntitlement,
        errSecNotAvailable,
    ]

    public static var defaultService: String {
        Bundle.main.bundleIdentifier ?? "SwiftKey.DefaultService"
    }

    public let configuration: SwiftKeyConfiguration
    public var debugLogHandler: SwiftKeyLogHandler?

    public init(
        configuration: SwiftKeyConfiguration = .init(),
        debugLogHandler: SwiftKeyLogHandler? = nil
    ) {
        self.configuration = configuration
        self.debugLogHandler = debugLogHandler
    }

    public convenience init(
        service: String? = nil,
        accessGroup: String? = nil,
        synchronizable: Bool = true,
        accessibility: KeychainAccessibility = .afterFirstUnlock,
        debugLogHandler: SwiftKeyLogHandler? = nil
    ) {
        self.init(
            configuration: SwiftKeyConfiguration(
                service: service ?? Self.defaultService,
                accessGroup: accessGroup,
                synchronizable: synchronizable,
                accessibility: accessibility
            ),
            debugLogHandler: debugLogHandler
        )
    }

    public func AddKey<T: Codable>(_ key: String, _ value: T) throws {
        try addKey(key, value)
    }

    public func addKey<T: Codable>(_ key: String, _ value: T) throws {
        do {
            try setValue(value, forKey: key, mode: .upsert)
            log(.debug, operation: "addKey", key: key, message: "Stored value.")
        } catch let error as SwiftKeyError {
            log(
                .error,
                operation: "addKey",
                key: key,
                message: error.localizedDescription,
                status: status(from: error)
            )
            throw error
        }
    }

    public func addKey(_ key: String, _ value: Data) throws {
        try setData(value, forKey: key)
    }

    public func updateKey<T: Codable>(_ key: String, _ value: T) throws {
        do {
            try setValue(value, forKey: key, mode: .updateOnly)
            log(.debug, operation: "updateKey", key: key, message: "Updated value.")
        } catch let error as SwiftKeyError {
            log(
                .error,
                operation: "updateKey",
                key: key,
                message: error.localizedDescription,
                status: status(from: error)
            )
            throw error
        }
    }

    public func updateKey(_ key: String, _ value: Data) throws {
        try setRawData(value, forKey: key, mode: .updateOnly)
    }

    public func setData(_ data: Data, forKey key: String) throws {
        do {
            try setRawData(data, forKey: key, mode: .upsert)
            log(.debug, operation: "setData", key: key, message: "Stored raw data.")
        } catch let error as SwiftKeyError {
            log(
                .error,
                operation: "setData",
                key: key,
                message: error.localizedDescription,
                status: status(from: error)
            )
            throw error
        }
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

    public func getInt(_ key: String, default defaultValue: Int) throws -> Int {
        try getKey(key, default: defaultValue, as: Int.self)
    }

    public func getDouble(_ key: String) throws -> Double? {
        try getKey(key, as: Double.self)
    }

    public func getDouble(_ key: String, default defaultValue: Double) throws -> Double {
        try getKey(key, default: defaultValue, as: Double.self)
    }

    public func getBool(_ key: String) throws -> Bool? {
        try getKey(key, as: Bool.self)
    }

    public func getBool(_ key: String, default defaultValue: Bool) throws -> Bool {
        try getKey(key, default: defaultValue, as: Bool.self)
    }

    public var isSynchronizableRequested: Bool {
        configuration.synchronizable
    }

    public func canUseSynchronizableStorage() -> Bool {
        guard configuration.synchronizable else {
            return false
        }

        let probeKey = "__swiftkey_sync_probe__"

        do {
            _ = try readRawData(forKey: probeKey, synchronizable: true)
            return true
        } catch let error as SwiftKeyError {
            return !shouldFallbackToLocalStorage(error)
        } catch {
            return false
        }
    }

    public func getData(forKey key: String) throws -> Data? {
        do {
            let validatedKey = try validateKey(key)
            let data = try readDataWithFallback(forKey: validatedKey)
            log(
                .debug,
                operation: "getData",
                key: key,
                message: data == nil ? "Value not found." : "Value loaded."
            )
            return data
        } catch let error as SwiftKeyError {
            log(
                .error,
                operation: "getData",
                key: key,
                message: error.localizedDescription,
                status: status(from: error)
            )
            throw error
        }
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
        do {
            let validatedKey = try validateKey(key)
            let didRemove = try removeDataWithFallback(forKey: validatedKey)
            log(
                .debug,
                operation: "removeKey",
                key: key,
                message: didRemove ? "Removed key." : "Key did not exist."
            )
            return didRemove
        } catch let error as SwiftKeyError {
            log(
                .error,
                operation: "removeKey",
                key: key,
                message: error.localizedDescription,
                status: status(from: error)
            )
            throw error
        }
    }

    public func removeAllKeys() throws {
        let keys = try allKeys()
        for key in keys {
            _ = try removeKey(key)
        }
        log(.info, operation: "removeAllKeys", message: "Cleared \(keys.count) keys.")
    }

    public func removeAllAvailableKeys() throws {
        for isSynchronizable in [false, true] {
            var query = serviceQuery(synchronizable: isSynchronizable)
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
        if !configuration.synchronizable {
            let found = try keysForQuery(synchronizable: false)
            log(.debug, operation: "allKeys", message: "Loaded \(found.count) keys.")
            return found
        }

        var combined = Set<String>()

        do {
            combined.formUnion(try keysForQuery(synchronizable: true))
        } catch let error as SwiftKeyError where shouldFallbackToLocalStorage(error) {
            // Sync is not available; continue with local keychain only.
            log(
                .warning,
                operation: "allKeys",
                message: "Sync unavailable. Using local keys.",
                status: status(from: error)
            )
        }

        combined.formUnion(try keysForQuery(synchronizable: false))
        let found = Array(combined).sorted()
        log(.debug, operation: "allKeys", message: "Loaded \(found.count) keys.")
        return found
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
        try writeDataWithFallback(data, forKey: validatedKey, mode: mode)
    }

    private func writeDataWithFallback(_ data: Data, forKey key: String, mode: WriteMode) throws {
        if !configuration.synchronizable {
            try writeRawData(data, forKey: key, mode: mode, synchronizable: false)
            return
        }

        do {
            try writeRawData(data, forKey: key, mode: mode, synchronizable: true)
        } catch let error as SwiftKeyError where shouldFallbackToLocalStorage(error) {
            log(
                .warning,
                operation: "writeDataWithFallback",
                key: key,
                message: "Sync write failed. Falling back to local write.",
                status: status(from: error)
            )
            try writeRawData(data, forKey: key, mode: mode, synchronizable: false)
        }
    }

    private func writeRawData(
        _ data: Data,
        forKey key: String,
        mode: WriteMode,
        synchronizable: Bool
    ) throws {
        switch mode {
        case .upsert:
            do {
                try addRawData(data, forKey: key, synchronizable: synchronizable)
            } catch SwiftKeyError.duplicateKey {
                try updateRawData(data, forKey: key, synchronizable: synchronizable)
            }
        case .updateOnly:
            try updateRawData(data, forKey: key, synchronizable: synchronizable)
        }
    }

    private func addRawData(_ data: Data, forKey key: String, synchronizable: Bool) throws {
        var query = keyQuery(for: key, synchronizable: synchronizable)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = configuration.accessibility.secValue

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw statusToError(status)
        }
    }

    private func updateRawData(_ data: Data, forKey key: String, synchronizable: Bool) throws {
        let searchQuery = keyQuery(for: key, synchronizable: synchronizable)
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

    private func readDataWithFallback(forKey key: String) throws -> Data? {
        if !configuration.synchronizable {
            return try readRawData(forKey: key, synchronizable: false)
        }

        do {
            if let syncData = try readRawData(forKey: key, synchronizable: true) {
                return syncData
            }
        } catch let error as SwiftKeyError where !shouldFallbackToLocalStorage(error) {
            throw error
        } catch let error as SwiftKeyError {
            log(
                .warning,
                operation: "readDataWithFallback",
                key: key,
                message: "Sync read failed. Falling back to local read.",
                status: status(from: error)
            )
        }

        return try readRawData(forKey: key, synchronizable: false)
    }

    private func readRawData(forKey key: String, synchronizable: Bool) throws -> Data? {
        var query = keyQuery(for: key, synchronizable: synchronizable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SwiftKeyError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw statusToError(status)
        }
    }

    private func removeDataWithFallback(forKey key: String) throws -> Bool {
        if !configuration.synchronizable {
            return try removeRawData(forKey: key, synchronizable: false)
        }

        var didDelete = false

        do {
            didDelete = try removeRawData(forKey: key, synchronizable: true) || didDelete
        } catch let error as SwiftKeyError where !shouldFallbackToLocalStorage(error) {
            throw error
        } catch let error as SwiftKeyError {
            log(
                .warning,
                operation: "removeDataWithFallback",
                key: key,
                message: "Sync delete failed. Falling back to local delete.",
                status: status(from: error)
            )
        }

        didDelete = try removeRawData(forKey: key, synchronizable: false) || didDelete
        return didDelete
    }

    private func removeRawData(forKey key: String, synchronizable: Bool) throws -> Bool {
        let query = keyQuery(for: key, synchronizable: synchronizable)
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

    private func encode<T: Codable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SwiftKeyError.encodingFailed
        }
    }

    private func decode<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SwiftKeyError.decodingFailed
        }
    }

    private func validateKey(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SwiftKeyError.invalidKey
        }
        return trimmed
    }

    private func keyQuery(for key: String, synchronizable: Bool) -> [String: Any] {
        var query = serviceQuery(synchronizable: synchronizable)
        query[kSecAttrAccount as String] = key
        return query
    }

    private func serviceQuery(synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
        ]

        query[kSecAttrSynchronizable as String] =
            synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any

        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func keysForQuery(synchronizable: Bool) throws -> [String] {
        var query = serviceQuery(synchronizable: synchronizable)
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

        throw SwiftKeyError.unexpectedData
    }

    private func shouldFallbackToLocalStorage(_ error: SwiftKeyError) -> Bool {
        guard case let .unhandledStatus(status) = error else {
            return false
        }
        return Self.syncFallbackStatuses.contains(status)
    }

    private func status(from error: SwiftKeyError) -> OSStatus? {
        guard case let .unhandledStatus(status) = error else {
            return nil
        }
        return status
    }

    private func log(
        _ level: SwiftKeyLogLevel,
        operation: String,
        key: String? = nil,
        message: String,
        status: OSStatus? = nil
    ) {
        guard let debugLogHandler else {
            return
        }

        debugLogHandler(
            SwiftKeyLogEntry(
                timestamp: Date(),
                level: level,
                operation: operation,
                key: key,
                message: message,
                status: status
            )
        )
    }

    private func statusToError(_ status: OSStatus) -> SwiftKeyError {
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
