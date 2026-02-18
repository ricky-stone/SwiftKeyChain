import Foundation
import Security

public enum SwiftKeyLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct SwiftKeyLogEntry: Sendable {
    public let timestamp: Date
    public let level: SwiftKeyLogLevel
    public let operation: String
    public let key: String?
    public let message: String
    public let status: OSStatus?

    public init(
        timestamp: Date,
        level: SwiftKeyLogLevel,
        operation: String,
        key: String?,
        message: String,
        status: OSStatus?
    ) {
        self.timestamp = timestamp
        self.level = level
        self.operation = operation
        self.key = key
        self.message = message
        self.status = status
    }
}

public typealias SwiftKeyLogHandler = @Sendable (SwiftKeyLogEntry) -> Void

public protocol SwiftKeyStore: AnyObject {
    func set<T: Codable>(_ key: String, _ value: T) throws
    func set(_ key: String, _ value: Data) throws
    func get<T: Codable>(_ key: String, as type: T.Type) throws -> T?
    func getData(forKey key: String) throws -> Data?
    func contains(_ key: String) throws -> Bool
    @discardableResult
    func remove(_ key: String) throws -> Bool
    func clear() throws
    func keys() throws -> [String]
    var isSynchronizableRequested: Bool { get }
    func canUseSynchronizableStorage() -> Bool
}

extension SwiftKeyStore {
    public func contains(_ key: String) throws -> Bool {
        try getData(forKey: key) != nil
    }

    public func setResult<T: Codable>(_ key: String, _ value: T) -> Result<Void, SwiftKeyError> {
        do {
            try set(key, value)
            return .success(())
        } catch {
            return .failure(asSwiftKeyError(error))
        }
    }

    public func getResult<T: Codable>(_ key: String, as type: T.Type = T.self) -> Result<T?, SwiftKeyError> {
        do {
            return .success(try get(key, as: type))
        } catch {
            return .failure(asSwiftKeyError(error))
        }
    }

    public func removeResult(_ key: String) -> Result<Bool, SwiftKeyError> {
        do {
            return .success(try remove(key))
        } catch {
            return .failure(asSwiftKeyError(error))
        }
    }

    public func clearResult() -> Result<Void, SwiftKeyError> {
        do {
            try clear()
            return .success(())
        } catch {
            return .failure(asSwiftKeyError(error))
        }
    }

    public func keysResult() -> Result<[String], SwiftKeyError> {
        do {
            return .success(try keys())
        } catch {
            return .failure(asSwiftKeyError(error))
        }
    }

    @discardableResult
    public func migrateKey(from oldKey: String, to newKey: String, overwrite: Bool = false) throws -> Bool {
        guard oldKey != newKey else {
            return try contains(oldKey)
        }

        guard let data = try getData(forKey: oldKey) else {
            return false
        }

        if !overwrite, try contains(newKey) {
            throw SwiftKeyError.duplicateKey
        }

        try set(newKey, data)
        _ = try remove(oldKey)
        return true
    }

    @discardableResult
    public func migrateModel<T: Codable>(
        from oldKey: String,
        to newKey: String,
        as type: T.Type = T.self,
        overwrite: Bool = false
    ) throws -> Bool {
        guard oldKey != newKey else {
            return try contains(oldKey)
        }

        guard let model = try get(oldKey, as: type) else {
            return false
        }

        if !overwrite, try contains(newKey) {
            throw SwiftKeyError.duplicateKey
        }

        try set(newKey, model)
        _ = try remove(oldKey)
        return true
    }

    public func setAsync<T: Codable>(_ key: String, _ value: T) async throws {
        try set(key, value)
    }

    public func getAsync<T: Codable>(_ key: String, as type: T.Type = T.self) async throws -> T? {
        try get(key, as: type)
    }

    @discardableResult
    public func removeAsync(_ key: String) async throws -> Bool {
        try remove(key)
    }

    public func keysAsync() async throws -> [String] {
        try keys()
    }

    public func clearAsync() async throws {
        try clear()
    }

    public func containsAsync(_ key: String) async throws -> Bool {
        try contains(key)
    }

    public func setResult<T: Codable>(_ key: SwiftKey.Key<T>, _ value: T) -> Result<Void, SwiftKeyError> {
        setResult(key.name, value)
    }

    public func getResult<T: Codable>(_ key: SwiftKey.Key<T>) -> Result<T?, SwiftKeyError> {
        getResult(key.name, as: T.self)
    }

    public func removeResult<T: Codable>(_ key: SwiftKey.Key<T>) -> Result<Bool, SwiftKeyError> {
        removeResult(key.name)
    }
}

extension SwiftKey: SwiftKeyStore {
    public func set<T: Codable>(_ key: String, _ value: T) throws {
        try addKey(key, value)
    }

    public func set(_ key: String, _ value: Data) throws {
        try setData(value, forKey: key)
    }

    public func get<T: Codable>(_ key: String, as type: T.Type) throws -> T? {
        try getKey(key, as: type)
    }

    public func contains(_ key: String) throws -> Bool {
        try containsKey(key)
    }

    @discardableResult
    public func remove(_ key: String) throws -> Bool {
        try removeKey(key)
    }

    public func clear() throws {
        try removeAllKeys()
    }

    public func keys() throws -> [String] {
        try allKeys()
    }
}

extension SwiftKey {
    public struct Key<Value: Codable>: Hashable, Sendable {
        public let name: String

        public init(_ name: String) {
            self.name = name
        }
    }

    public struct Namespace {
        private let prefix: String
        private let store: SwiftKeyStore

        public init(_ prefix: String, store: SwiftKeyStore) {
            let cleaned = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            self.prefix = cleaned.isEmpty ? "default" : cleaned
            self.store = store
        }

        public var fullPrefix: String {
            prefix
        }

        public func set<T: Codable>(_ key: String, _ value: T) throws {
            try store.set(scoped(key), value)
        }

        public func set(_ key: String, _ value: Data) throws {
            try store.set(scoped(key), value)
        }

        public func get<T: Codable>(_ key: String, as type: T.Type = T.self) throws -> T? {
            try store.get(scoped(key), as: type)
        }

        public func get<T: Codable>(
            _ key: String,
            default defaultValue: T,
            as type: T.Type = T.self
        ) throws -> T {
            try store.get(scoped(key), as: type) ?? defaultValue
        }

        @discardableResult
        public func remove(_ key: String) throws -> Bool {
            try store.remove(scoped(key))
        }

        public func contains(_ key: String) throws -> Bool {
            try store.contains(scoped(key))
        }

        public func keys() throws -> [String] {
            let namespacedPrefix = "\(prefix)."
            return try store.keys()
                .filter { $0.hasPrefix(namespacedPrefix) }
                .map { String($0.dropFirst(namespacedPrefix.count)) }
                .sorted()
        }

        public func clear() throws {
            for key in try keys() {
                _ = try store.remove(scoped(key))
            }
        }

        public func key<T: Codable>(_ key: String, as type: T.Type = T.self) -> SwiftKey.Key<T> {
            SwiftKey.Key<T>(scoped(key))
        }

        private func scoped(_ key: String) -> String {
            "\(prefix).\(key)"
        }
    }

    public struct Diagnosis: Sendable {
        public let service: String
        public let accessGroup: String?
        public let synchronizableRequested: Bool
        public let synchronizableAvailable: Bool
        public let notes: [String]

        public init(
            service: String,
            accessGroup: String?,
            synchronizableRequested: Bool,
            synchronizableAvailable: Bool,
            notes: [String]
        ) {
            self.service = service
            self.accessGroup = accessGroup
            self.synchronizableRequested = synchronizableRequested
            self.synchronizableAvailable = synchronizableAvailable
            self.notes = notes
        }
    }

    public final class Beginner {
        private let store: SwiftKeyStore

        public private(set) var lastError: SwiftKeyError?
        public var lastErrorMessage: String? {
            lastError?.localizedDescription
        }

        public init(store: SwiftKeyStore = SwiftKey()) {
            self.store = store
        }

        public convenience init(configuration: SwiftKeyConfiguration) {
            self.init(store: SwiftKey(configuration: configuration))
        }

        @discardableResult
        public func setString(_ key: String, _ value: String) -> Bool {
            write { try store.set(key, value) }
        }

        @discardableResult
        public func setInt(_ key: String, _ value: Int) -> Bool {
            write { try store.set(key, value) }
        }

        @discardableResult
        public func setBool(_ key: String, _ value: Bool) -> Bool {
            write { try store.set(key, value) }
        }

        @discardableResult
        public func setDouble(_ key: String, _ value: Double) -> Bool {
            write { try store.set(key, value) }
        }

        @discardableResult
        public func setData(_ key: String, _ value: Data) -> Bool {
            write { try store.set(key, value) }
        }

        @discardableResult
        public func setModel<T: Codable>(_ key: String, _ model: T) -> Bool {
            write { try store.set(key, model) }
        }

        public func getString(_ key: String) -> String? {
            read { try store.get(key, as: String.self) }
        }

        public func getString(_ key: String, default defaultValue: String) -> String {
            read(default: defaultValue) { try store.get(key, as: String.self) }
        }

        public func getInt(_ key: String) -> Int? {
            read { try store.get(key, as: Int.self) }
        }

        public func getInt(_ key: String, default defaultValue: Int) -> Int {
            read(default: defaultValue) { try store.get(key, as: Int.self) }
        }

        public func getBool(_ key: String) -> Bool? {
            read { try store.get(key, as: Bool.self) }
        }

        public func getBool(_ key: String, default defaultValue: Bool) -> Bool {
            read(default: defaultValue) { try store.get(key, as: Bool.self) }
        }

        public func getDouble(_ key: String) -> Double? {
            read { try store.get(key, as: Double.self) }
        }

        public func getDouble(_ key: String, default defaultValue: Double) -> Double {
            read(default: defaultValue) { try store.get(key, as: Double.self) }
        }

        public func getData(_ key: String) -> Data? {
            read { try store.getData(forKey: key) }
        }

        public func getModel<T: Codable>(_ key: String, as type: T.Type = T.self) -> T? {
            read { try store.get(key, as: type) }
        }

        public func getModel<T: Codable>(
            _ key: String,
            default defaultValue: T,
            as type: T.Type = T.self
        ) -> T {
            read(default: defaultValue) { try store.get(key, as: type) }
        }

        @discardableResult
        public func remove(_ key: String) -> Bool {
            do {
                let didRemove = try store.remove(key)
                lastError = nil
                return didRemove
            } catch {
                lastError = asSwiftKeyError(error)
                return false
            }
        }

        public func contains(_ key: String) -> Bool {
            do {
                let doesExist = try store.contains(key)
                lastError = nil
                return doesExist
            } catch {
                lastError = asSwiftKeyError(error)
                return false
            }
        }

        public func keys() -> [String] {
            do {
                let all = try store.keys()
                lastError = nil
                return all
            } catch {
                lastError = asSwiftKeyError(error)
                return []
            }
        }

        @discardableResult
        public func clear() -> Bool {
            write { try store.clear() }
        }

        private func write(_ action: () throws -> Void) -> Bool {
            do {
                try action()
                lastError = nil
                return true
            } catch {
                lastError = asSwiftKeyError(error)
                return false
            }
        }

        private func read<T>(_ action: () throws -> T?) -> T? {
            do {
                let value = try action()
                lastError = nil
                return value
            } catch {
                lastError = asSwiftKeyError(error)
                return nil
            }
        }

        private func read<T>(default defaultValue: T, _ action: () throws -> T?) -> T {
            read(action) ?? defaultValue
        }
    }

    public func namespace(_ prefix: String) -> Namespace {
        SwiftKey.Namespace(prefix, store: self)
    }

    public func Namespace(_ prefix: String) -> Namespace {
        namespace(prefix)
    }

    public var beginner: Beginner {
        Beginner(store: self)
    }

    public func get<T: Codable>(_ key: String) throws -> T? {
        try get(key, as: T.self)
    }

    public func get<T: Codable>(_ key: Key<T>) throws -> T? {
        try get(key.name, as: T.self)
    }

    public func get<T: Codable>(_ key: Key<T>, default defaultValue: T) throws -> T {
        try get(key.name, as: T.self) ?? defaultValue
    }

    public func set<T: Codable>(_ key: Key<T>, _ value: T) throws {
        try set(key.name, value)
    }

    @discardableResult
    public func remove<T: Codable>(_ key: Key<T>) throws -> Bool {
        try remove(key.name)
    }

    @discardableResult
    public func migrate<T: Codable>(from oldKey: Key<T>, to newKey: Key<T>, overwrite: Bool = false) throws -> Bool {
        try migrateModel(from: oldKey.name, to: newKey.name, as: T.self, overwrite: overwrite)
    }

    public func diagnose() -> Diagnosis {
        var notes: [String] = []

        let trimmedService = configuration.service.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedService.isEmpty {
            notes.append("Service name is empty. Use a stable app-specific service string.")
        } else {
            notes.append("Service is configured as '\(configuration.service)'.")
        }

        if let accessGroup = configuration.accessGroup {
            if accessGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes.append("Access group is empty; remove it or provide a valid entitlement group.")
            } else {
                notes.append("Access group is set. Ensure your app entitlements include it.")
            }
        } else {
            notes.append("No access group set. This is fine for single-app usage.")
        }

        let syncAvailable = canUseSynchronizableStorage()
        if configuration.synchronizable {
            if syncAvailable {
                notes.append("Sync is requested and currently available.")
            } else {
                notes.append("Sync is requested but unavailable right now; SwiftKey will fall back to local storage.")
            }
        } else {
            notes.append("Sync is disabled by configuration.")
        }

        notes.append("Accessibility is '\(String(describing: configuration.accessibility))'.")

        return Diagnosis(
            service: configuration.service,
            accessGroup: configuration.accessGroup,
            synchronizableRequested: configuration.synchronizable,
            synchronizableAvailable: syncAvailable,
            notes: notes
        )
    }
}

public final class InMemorySwiftKeyStore: SwiftKeyStore {
    public let isSynchronizableRequested: Bool = false

    private var values: [String: Data]
    private let lock = NSLock()

    public init(seedValues: [String: Data] = [:]) {
        self.values = seedValues
    }

    public func set<T: Codable>(_ key: String, _ value: T) throws {
        if let data = value as? Data {
            try set(key, data)
            return
        }

        do {
            let encoded = try JSONEncoder().encode(value)
            try set(key, encoded)
        } catch {
            throw SwiftKeyError.encodingFailed
        }
    }

    public func set(_ key: String, _ value: Data) throws {
        let validated = try validatedKey(key)
        lock.lock()
        values[validated] = value
        lock.unlock()
    }

    public func get<T: Codable>(_ key: String, as type: T.Type) throws -> T? {
        if type == Data.self {
            return try getData(forKey: key) as? T
        }

        guard let data = try getData(forKey: key) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SwiftKeyError.decodingFailed
        }
    }

    public func getData(forKey key: String) throws -> Data? {
        let validated = try validatedKey(key)
        lock.lock()
        let data = values[validated]
        lock.unlock()
        return data
    }

    public func contains(_ key: String) throws -> Bool {
        try getData(forKey: key) != nil
    }

    @discardableResult
    public func remove(_ key: String) throws -> Bool {
        let validated = try validatedKey(key)
        lock.lock()
        let existing = values.removeValue(forKey: validated)
        lock.unlock()
        return existing != nil
    }

    public func clear() throws {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }

    public func keys() throws -> [String] {
        lock.lock()
        let all = Array(values.keys).sorted()
        lock.unlock()
        return all
    }

    public func canUseSynchronizableStorage() -> Bool {
        false
    }

    private func validatedKey(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SwiftKeyError.invalidKey
        }
        return trimmed
    }
}

private func asSwiftKeyError(_ error: Error) -> SwiftKeyError {
    if let keyError = error as? SwiftKeyError {
        return keyError
    }
    return .unhandledStatus(errSecInternalError)
}
