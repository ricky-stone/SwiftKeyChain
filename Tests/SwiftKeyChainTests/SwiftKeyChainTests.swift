import Foundation
import Testing
@testable import SwiftKeyChain

private struct User: Codable, Equatable {
    let name: String
    let age: Int
}

struct SwiftKeyChainTests {
    private func makeKeychain() -> SwiftKeyChain {
        SwiftKeyChain(
            service: "SwiftKeyChain.Tests.\(UUID().uuidString)",
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

        var receivedError: SwiftKeyChainError?
        do {
            try kc.updateKey("missing", "value")
        } catch let error as SwiftKeyChainError {
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
}
