# SwiftKeyChain

[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftKeyChain?include_prereleases&label=release)](https://github.com/ricky-stone/SwiftKeyChain/releases)
[![CI](https://github.com/ricky-stone/SwiftKeyChain/actions/workflows/ci.yml/badge.svg)](https://github.com/ricky-stone/SwiftKeyChain/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20iPadOS%20%7C%20watchOS%20%7C%20tvOS-blue)](https://developer.apple.com/documentation/security/keychain_services)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-orange)](https://swift.org)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftKeyChain)](https://github.com/ricky-stone/SwiftKeyChain/blob/main/LICENSE)

Simple, beginner-friendly Keychain wrapper for Apple platforms.

[Install](#installation) | [Basic Usage](#basic-usage) | [DoCatch-usage](#docatch-usage) | [Sync-fail-safe](#sync-fail-safe)

## Why SwiftKeyChain?

- Easy API for add/get/update/delete.
- Works with primitive values and `Codable` models.
- Optional iCloud Keychain sync (`synchronizable`) with automatic local fallback.
- Supports custom `service` and optional `accessGroup`.
- Can list keys and clear keys.

## Installation

### Xcode (Swift Package Manager)

1. Open `File > Add Packages...`
2. Paste:
   `https://github.com/ricky-stone/SwiftKeyChain.git`
3. Select `Up to Next Major` from `0.0.1`.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/ricky-stone/SwiftKeyChain.git", from: "0.0.1")
]
```

## Basic Usage

```swift
import SwiftKeyChain

let kc = SwiftKeyChain()

try? kc.AddKey("KeyName", "Value")
let value = try? kc.getKey("KeyName")
print(value ?? "not found")
```

### Store primitives

```swift
try? kc.AddKey("launchCount", 42)
try? kc.AddKey("isPremium", true)
try? kc.AddKey("pi", 3.14159)

let launchCount = try? kc.getInt("launchCount")
let isPremium = try? kc.getBool("isPremium")
let pi = try? kc.getDouble("pi")
```

### Store a model

```swift
struct User: Codable {
    let name: String
    let age: Int
}

let user = User(name: "Ricky", age: 29)
try? kc.AddKey("User", user)

let savedUser = try? kc.getModel("User", as: User.self)
```

## Do/Catch Usage

### Add and read safely

```swift
import SwiftKeyChain

func saveAndRead() {
    let kc = SwiftKeyChain()

    do {
        try kc.AddKey("Token", "abc123")
        let token = try kc.getKey("Token")
        print("Token:", token ?? "missing")
    } catch {
        print("Keychain error:", error.localizedDescription)
    }
}
```

### Update, delete, list, clear

```swift
func manageKeys() {
    let kc = SwiftKeyChain()

    do {
        try kc.AddKey("Plan", "free")
        try kc.updateKey("Plan", "pro")

        let all = try kc.allKeys()
        print("All keys:", all)

        let removed = try kc.deleteKey("Plan")
        print("Removed Plan:", removed)

        try kc.removeAllKeys()
    } catch {
        print("Keychain error:", error.localizedDescription)
    }
}
```

## Typed Reads (Different "Casting" Styles)

SwiftKeyChain decodes by type. You can retrieve values in multiple beginner-friendly ways.

### 1) Explicit type with `as:`

```swift
let count = try kc.getKey("Count", as: Int.self)
let user = try kc.getKey("User", as: User.self)
```

### 2) Model helper

```swift
let user = try kc.getModel("User", as: User.self)
```

### 3) Type inference from variable

```swift
let count: Int? = try kc.getKey("Count")
let user: User? = try kc.getKey("User")
```

### 4) Default fallback values

```swift
let username = try kc.getKey("username", "Guest")
let retryCount = try kc.getInt("retryCount", default: 3)
let shouldOnboard = try kc.getBool("shouldOnboard", default: true)
let taxRate = try kc.getDouble("taxRate", default: 0.2)

// Generic fallback also works for Codable models:
let guestUser = User(name: "Guest", age: 0)
let user = try kc.getKey("User", default: guestUser, as: User.self)
```

Fallback support:
- Primitive helpers: `String`, `Int`, `Bool`, `Double`
- Generic fallback: any `Codable` type (including your own models)

## Raw Data

```swift
let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])

try kc.setData(bytes, forKey: "Blob")
let blob = try kc.getData(forKey: "Blob")
```

## Sync Fail-Safe

```swift
let kc = SwiftKeyChain(
    service: "com.example.myapp",
    accessGroup: nil,
    synchronizable: true,
    accessibility: .afterFirstUnlock
)
```

What happens when `synchronizable` is `true`:
- SwiftKeyChain first tries iCloud-synced Keychain operations.
- If sync is unavailable (for example entitlement or keychain availability issues), it falls back to local non-sync storage automatically, so data can still be stored.

Useful helpers:

```swift
let wantsSync = kc.isSynchronizableRequested
let canUseSyncNow = kc.canUseSynchronizableStorage() // best-effort runtime check
```

Important notes:
- Apple does not expose a simple public API that directly tells you whether the user has iCloud Keychain toggled on.
- `canUseSynchronizableStorage()` is a best-effort operational check from your app context.
- Access groups require proper entitlements/provisioning.

## Configuration

```swift
let kc = SwiftKeyChain(
    service: "com.mycompany.myapp",
    accessGroup: nil,
    synchronizable: true,
    accessibility: .afterFirstUnlock
)
```

## API Overview

- `AddKey(_:_: )` / `addKey(_:_: )`
- `updateKey(_:_: )`
- `getKey(_:)`
- `getKey(_:default:as:)`
- `getModel(_:as:)`
- `getInt(_:)`, `getInt(_:default:)`
- `getBool(_:)`, `getBool(_:default:)`
- `getDouble(_:)`, `getDouble(_:default:)`
- `getData(forKey:)`
- `containsKey(_:)`
- `deleteKey(_:)` / `removeKey(_:)`
- `allKeys()`
- `removeAllKeys()`
- `removeAllAvailableKeys()`
- `isSynchronizableRequested`
- `canUseSynchronizableStorage()`

## Testing

```bash
swift test
```

## License

MIT License.

Copyright (c) 2026 Ricky Stone.

## Author

Created by Ricky Stone.
