# SwiftKey

[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftKey?include_prereleases&label=release)](https://github.com/ricky-stone/SwiftKey/releases)
[![CI](https://github.com/ricky-stone/SwiftKey/actions/workflows/ci.yml/badge.svg)](https://github.com/ricky-stone/SwiftKey/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20iPadOS%20%7C%20watchOS%20%7C%20tvOS-blue)](https://developer.apple.com/documentation/security/keychain_services)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-orange)](https://swift.org)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftKey)](https://github.com/ricky-stone/SwiftKey/blob/main/LICENSE)

Beginner-friendly Keychain library for Apple platforms.

## 30-Second Start

```swift
import SwiftKey

let key = SwiftKey.Beginner()

key.setString("username", "Ricky")
let username = key.getString("username", default: "Guest")
print(username)

if let error = key.lastErrorMessage {
    print("SwiftKey error:", error)
}
```

This path is non-throwing and easiest for beginners.

## Installation

### Xcode (SPM)

1. Open `File > Add Packages...`
2. Use: `https://github.com/ricky-stone/SwiftKey.git`
3. Select `Up to Next Major` from `1.1.0`

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/ricky-stone/SwiftKey.git", from: "1.1.0")
]
```

## Choose Your API Style

- `SwiftKey.Beginner`: no `try/catch`, returns defaults and tracks `lastErrorMessage`.
- `SwiftKey`: `throws` API for full control.
- `SwiftKeyStore` + `Result` helpers: good for app service layers.
- `async` wrappers: same behavior in async contexts.

## Beginner API (No Throws)

```swift
import SwiftKey

let key = SwiftKey.Beginner()

key.setString("token", "abc123")
key.setInt("launchCount", 1)
key.setBool("isPro", true)
key.setDouble("taxRate", 0.2)

let token = key.getString("token", default: "")
let launchCount = key.getInt("launchCount", default: 0)
let isPro = key.getBool("isPro", default: false)
let taxRate = key.getDouble("taxRate", default: 0)
```

### Beginner model storage

```swift
struct User: Codable {
    let name: String
    let age: Int
}

let key = SwiftKey.Beginner()
let user = User(name: "Ricky", age: 29)

key.setModel("user", user)
let storedUser = key.getModel("user", as: User.self)
```

### Beginner error handling

```swift
let key = SwiftKey.Beginner()
_ = key.setString("   ", "bad")

if let message = key.lastErrorMessage {
    print("Last error:", message)
}
```

## Core API (Throws)

```swift
import SwiftKey

let key = SwiftKey()

try key.addKey("username", "Ricky")
let username = try key.getKey("username", as: String.self)

try key.updateKey("username", "Ricky Stone")
let removed = try key.removeKey("username")
print("Removed:", removed)
```

### Plain aliases

These are available if you prefer simpler names.

```swift
try key.set("username", "Ricky")
let value: String? = try key.get("username")
let exists = try key.contains("username")
let removed = try key.remove("username")
try key.clear()
```

## Typed Keys (`Key<Value>`)

```swift
let userKey = SwiftKey.Key<User>("profile.user")

try key.set(userKey, User(name: "Ricky", age: 29))
let user = try key.get(userKey)
```

Typed keys reduce string typo mistakes in app code.

## Namespaces

Use namespaces to group keys.

```swift
let auth = key.namespace("auth")

try auth.set("token", "abc123")
let token = try auth.get("token", as: String.self)
let keys = try auth.keys()   // ["token"]
```

You can also build namespaced typed keys.

```swift
let namespacedUserKey = auth.key("user", as: User.self)
try key.set(namespacedUserKey, User(name: "Ricky", age: 29))
```

## Sync Fail-Safe

```swift
let key = SwiftKey(
    service: "com.example.myapp",
    accessGroup: nil,
    synchronizable: true,
    accessibility: .afterFirstUnlock
)
```

When `synchronizable` is `true`:
- SwiftKey tries iCloud-synced Keychain first.
- If sync fails due availability/entitlement issues, SwiftKey falls back to local non-sync storage.

Helpers:

```swift
let syncRequested = key.isSynchronizableRequested
let syncAvailable = key.canUseSynchronizableStorage()
```

## Diagnose and Debug Logging

### Diagnose configuration

```swift
let report = key.diagnose()
print(report.notes.joined(separator: "\n"))
```

### Optional debug logging hook

```swift
let key = SwiftKey(debugLogHandler: { entry in
    print("[\(entry.level.rawValue)] \(entry.operation): \(entry.message)")
})
```

## Result-Based API

```swift
let result = key.setResult("token", "abc123")

switch result {
case .success:
    print("saved")
case .failure(let error):
    print(error.localizedDescription)
}
```

Also available:
- `getResult`
- `removeResult`
- `clearResult`
- `keysResult`

## Async Wrappers

```swift
try await key.setAsync("token", "abc123")
let token: String? = try await key.getAsync("token", as: String.self)
let removed = try await key.removeAsync("token")
```

## Migration Helpers

```swift
try key.addKey("token", "abc123")
try key.migrateKey(from: "token", to: "auth.token")

try key.addKey("user.old", User(name: "Ricky", age: 29))
try key.migrateModel(from: "user.old", to: "user.current", as: User.self)
```

## In-Memory Store for Unit Tests

`InMemorySwiftKeyStore` is useful for deterministic tests without touching device keychain.

```swift
let store: SwiftKeyStore = InMemorySwiftKeyStore()
try store.set("username", "Ricky")
let username = try store.get("username", as: String.self)
```

## Error Glossary (Common)

- `invalidKey`: key is empty or whitespace.
- `duplicateKey`: target key exists when overwrite is not allowed.
- `keyNotFound`: requested key does not exist.
- `encodingFailed`: `Codable` value could not encode.
- `decodingFailed`: stored data does not match requested type.
- `unhandledStatus(code)`: underlying Keychain status from Security framework.

## Testing

```bash
swift test
```

## License

MIT License

Copyright (c) 2026 Ricky Stone
