# SwiftKeyChain

[![Release](https://img.shields.io/github/v/release/ricky-stone/SwiftKeyChain?include_prereleases&label=release)](https://github.com/ricky-stone/SwiftKeyChain/releases)
[![CI](https://github.com/ricky-stone/SwiftKeyChain/actions/workflows/ci.yml/badge.svg)](https://github.com/ricky-stone/SwiftKeyChain/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20iPadOS%20%7C%20watchOS%20%7C%20tvOS-blue)](https://developer.apple.com/documentation/security/keychain_services)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange)](https://swift.org)
[![License](https://img.shields.io/github/license/ricky-stone/SwiftKeyChain)](https://github.com/ricky-stone/SwiftKeyChain/blob/main/LICENSE)

Simple, beginner-friendly Keychain wrapper for Apple platforms.

[Get Started](#installation) | [Examples](#quick-start) | [Releases](https://github.com/ricky-stone/SwiftKeyChain/releases)

## Why SwiftKeyChain?

- Very easy API for adding/getting/updating/deleting values.
- Works with primitive types (`String`, `Int`, `Bool`, `Double`) and your own `Codable` models.
- Supports iCloud Keychain sync (`synchronizable`) when available.
- Supports custom keychain access groups for shared keychains.
- Includes helpers for listing keys and clearing all keys for your app/service.

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, open `File > Add Packages...`
2. Paste:
   `https://github.com/ricky-stone/SwiftKeyChain.git`
3. Choose version rule: `Up to Next Major` from `0.0.1`.

### Swift Package Manager (`Package.swift`)

```swift
dependencies: [
    .package(url: "https://github.com/ricky-stone/SwiftKeyChain.git", from: "0.0.1")
]
```

## Quick Start

```swift
import SwiftKeyChain

let kc = SwiftKeyChain()
try kc.AddKey("KeyName", "Value")

let value = try kc.getKey("KeyName")
print(value ?? "not found")
```

### Get with default fallback

```swift
let username = try kc.getKey("username", "Guest")
```

### Store primitive types

```swift
try kc.AddKey("launchCount", 42)
try kc.AddKey("isPremium", true)
try kc.AddKey("pi", 3.14159)

let launchCount = try kc.getInt("launchCount")
let isPremium = try kc.getBool("isPremium")
let pi = try kc.getDouble("pi")
```

### Store your own model

```swift
struct User: Codable {
    let name: String
}

let user = User(name: "Ricky")
try kc.AddKey("User", user)

let savedUser = try kc.getModel("User", as: User.self)
```

### Update, delete, and clear

```swift
try kc.updateKey("KeyName", "NewValue")

let deleted = try kc.deleteKey("KeyName")
print("Deleted:", deleted)

let keys = try kc.allKeys()
print(keys)

try kc.removeAllKeys()
```

### Raw data support

```swift
let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
try kc.setData(data, forKey: "Blob")

let blob = try kc.getData(forKey: "Blob")
```

## Configuration

```swift
let kc = SwiftKeyChain(
    service: "com.example.myapp",
    accessGroup: nil,              // set if you need shared keychain group
    synchronizable: true,          // iCloud Keychain sync (if enabled on device/account)
    accessibility: .afterFirstUnlock
)
```

Notes:
- `synchronizable: true` requires iCloud Keychain to be enabled on the user device/account.
- Access groups require correct app entitlements and provisioning setup.
- `removeAllKeys()` clears keys for the current `service` and configuration.

## API Overview

- `AddKey(_:_: )` / `addKey(_:_: )`
- `updateKey(_:_: )`
- `getKey(_:)`
- `getKey(_:default:as:)`
- `getModel(_:as:)`
- `getData(forKey:)`
- `getInt(_:)`, `getDouble(_:)`, `getBool(_:)`
- `containsKey(_:)`
- `deleteKey(_:)` / `removeKey(_:)`
- `allKeys()`
- `removeAllKeys()`

## Testing

```bash
swift test
```

## License

MIT
