import Foundation
import Testing
@testable import SwiftKey

private struct User: Codable, Equatable {
    let name: String
    let age: Int
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var entries: [SwiftKeyLogEntry] = []

    func append(_ entry: SwiftKeyLogEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }
}

struct SwiftKeyTests {
    private func makeKeychain() -> SwiftKey {
        SwiftKey(
            service: "SwiftKey.Tests.\(UUID().uuidString)",
            synchronizable: false
        )
    }

    @Test("Stores and reads primitive values")
    func storesAndReadsPrimitives() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        try kc.AddKey("username", "Ricky")
        try kc.AddKey("age", 29)
        try kc.AddKey("isPro", true)

        #expect(try kc.getKey("username") == "Ricky")
        #expect(try kc.getInt("age") == 29)
        #expect(try kc.getBool("isPro") == true)
        #expect(try kc.containsKey("username") == true)
        #expect(try kc.getInt("missing-int", default: 0) == 0)
        #expect(try kc.getDouble("missing-double", default: 2.5) == 2.5)
        #expect(try kc.getBool("missing-bool", default: false) == false)
    }

    @Test("Stores and reads Codable models")
    func storesAndReadsModels() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        let user = User(name: "Ricky", age: 29)
        try kc.AddKey("user", user)

        let savedUser = try kc.getModel("user", as: User.self)
        #expect(savedUser == user)
    }

    @Test("Supports type inference when reading values")
    func supportsTypeInference() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        let user = User(name: "Ricky", age: 29)
        try kc.AddKey("count", 7)
        try kc.AddKey("user", user)

        let count: Int? = try kc.getKey("count")
        let savedUser: User? = try kc.getKey("user")

        #expect(count == 7)
        #expect(savedUser == user)
    }

    @Test("Updates existing keys")
    func updatesKeys() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        try kc.AddKey("plan", "free")
        try kc.updateKey("plan", "pro")

        #expect(try kc.getKey("plan") == "pro")
    }

    @Test("Returns keyNotFound when update target is missing")
    func updateMissingKeyFails() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        var receivedError: SwiftKeyError?
        do {
            try kc.updateKey("missing", "value")
        } catch let error as SwiftKeyError {
            receivedError = error
        }

        #expect(receivedError == .keyNotFound)
    }

    @Test("Reads and writes raw data")
    func readsAndWritesRawData() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        let data = Data([0x10, 0x20, 0x30, 0x40])
        try kc.setData(data, forKey: "blob")

        #expect(try kc.getData(forKey: "blob") == data)
        #expect(try kc.getKey("blob", as: Data.self) == data)
    }

    @Test("Lists and removes keys")
    func listsAndRemovesKeys() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        try kc.AddKey("first", "A")
        try kc.AddKey("second", "B")
        try kc.AddKey("third", "C")

        let keys = try kc.allKeys()
        #expect(Set(keys) == Set(["first", "second", "third"]))

        #expect(try kc.deleteKey("second") == true)
        #expect(try kc.getKey("second") == nil)

        try kc.removeAllKeys()
        #expect(try kc.allKeys().isEmpty)
    }

    @Test("Returns default value when key is missing")
    func returnsDefaultForMissingKey() throws {
        let kc = makeKeychain()
        defer { try? kc.removeAllKeys() }

        let username = try kc.getKey("username", default: "Guest")
        #expect(username == "Guest")
    }

    @Test("Sync check is false when sync is not requested")
    func syncCheckIsFalseWhenSyncDisabled() {
        let kc = SwiftKey(
            service: "SwiftKey.Tests.\(UUID().uuidString)",
            synchronizable: false
        )

        #expect(kc.isSynchronizableRequested == false)
        #expect(kc.canUseSynchronizableStorage() == false)
    }

    @Test("Beginner API is non-throwing and tracks last error")
    func beginnerApiTracksErrors() {
        let beginner = SwiftKey.Beginner(store: InMemorySwiftKeyStore())

        #expect(beginner.setString("username", "Ricky") == true)
        #expect(beginner.getString("username", default: "Guest") == "Ricky")
        #expect(beginner.getInt("missing-int", default: 99) == 99)
        #expect(beginner.setModel("user", User(name: "Ricky", age: 29)) == true)
        #expect(beginner.getModel("user", as: User.self) == User(name: "Ricky", age: 29))
        #expect(beginner.remove("username") == true)

        #expect(beginner.setString(" ", "bad") == false)
        #expect(beginner.lastError != nil)
        #expect(beginner.lastErrorMessage != nil)
    }

    @Test("Result and migration helpers work")
    func resultAndMigrationHelpersWork() {
        let store: SwiftKeyStore = InMemorySwiftKeyStore()

        #expect(store.setResult("token", "abc").isSuccess)
        #expect(store.getResult("token", as: String.self).successValue == "abc")
        #expect((try? store.migrateKey(from: "token", to: "auth.token")) == true)
        #expect((try? store.contains("token")) == false)
        #expect(store.getResult("auth.token", as: String.self).successValue == "abc")
    }

    @Test("Typed keys and namespaces work")
    func typedKeysAndNamespacesWork() throws {
        let store: SwiftKeyStore = InMemorySwiftKeyStore()
        let namespace = SwiftKey.Namespace("auth", store: store)

        try namespace.set("token", "secret")
        #expect(try namespace.get("token", as: String.self) == "secret")
        #expect(try store.get("auth.token", as: String.self) == "secret")
        #expect(try namespace.keys() == ["token"])

        let typedKey = namespace.key("user", as: User.self)
        let user = User(name: "Ricky", age: 29)
        try store.set(typedKey.name, user)
        #expect(try store.get(typedKey.name, as: User.self) == user)

        try namespace.clear()
        #expect(try namespace.keys().isEmpty)
    }

    @Test("In-memory store supports async helpers")
    func inMemoryAsyncHelpers() async throws {
        let store: SwiftKeyStore = InMemorySwiftKeyStore()

        try await store.setAsync("counter", 1)
        let count = try await store.getAsync("counter", as: Int.self)
        #expect(count == 1)
        #expect(try await store.containsAsync("counter") == true)
        #expect(try await store.keysAsync().contains("counter") == true)
        #expect(try await store.removeAsync("counter") == true)
    }

    @Test("Diagnosis and debug logging provide useful output")
    func diagnosisAndLoggingWork() throws {
        let recorder = LogRecorder()
        let kc = SwiftKey(
            service: "SwiftKey.Tests.\(UUID().uuidString)",
            synchronizable: false,
            debugLogHandler: { entry in
                recorder.append(entry)
            }
        )

        try kc.addKey("log-check", "ok")
        _ = try kc.getKey("log-check")
        _ = try kc.removeKey("log-check")

        let diagnosis = kc.diagnose()
        #expect(diagnosis.service.contains("SwiftKey.Tests."))
        #expect(diagnosis.notes.isEmpty == false)
        #expect(recorder.entries.isEmpty == false)
    }
}

private extension Result {
    var successValue: Success? {
        guard case let .success(value) = self else {
            return nil
        }
        return value
    }

    var isSuccess: Bool {
        successValue != nil
    }
}
