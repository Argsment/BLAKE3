# BLAKE3-Swift

A pure Swift implementation of the [BLAKE3](https://github.com/BLAKE3-team/BLAKE3) cryptographic hash function.

BLAKE3 is a cryptographic hash function that is much faster than MD5, SHA-1, SHA-2, SHA-3, and BLAKE2, while being secure, unlike MD5 and SHA-1.

## Features

- Pure Swift
- SIMD-accelerated 4-way parallel hashing on arm64 (Apple Silicon / NEON) and x86_64 (SSE)
- Wide subtree compression for large inputs
- All three BLAKE3 modes: hash, keyed hash, and key derivation
- Extendable output (XOF) with seeking support
- Incremental (streaming) hashing
- Verified against the full official BLAKE3 test vector suite

## Installation

Add this package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Argsment/BLAKE3.git", from: "1.0.0"),
]
```

Then add `"BLAKE3"` to your target's dependencies:

```swift
.target(name: "YourTarget", dependencies: ["BLAKE3"]),
```

## Usage

### Hash

```swift
import BLAKE3

// One-shot
let hash = blake3Hash(Array("hello world".utf8))

// Incremental
var hasher = BLAKE3Hasher()
hasher.update(Array("hello ".utf8))
hasher.update(Array("world".utf8))
let hash = hasher.finalize() // 32-byte [UInt8]
```

### Keyed Hash (MAC)

```swift
let key: [UInt8] = ... // exactly 32 bytes
var hasher = BLAKE3Hasher(key: key)
hasher.update(message)
let mac = hasher.finalize()
```

### Key Derivation (KDF)

```swift
var hasher = BLAKE3Hasher(derivingKeyFromContext: "myapp 2025-01-01 session key")
hasher.update(inputKeyMaterial)
let derivedKey = hasher.finalize() // 32 bytes
```

### Extended Output (XOF)

```swift
var hasher = BLAKE3Hasher()
hasher.update(data)
let output = hasher.finalize(outputLength: 128) // any length
```

### Seeking

```swift
let partial = hasher.finalize(seek: 64, outputLength: 32) // bytes 64..95 of the output stream
```

### Reset

```swift
var hasher = BLAKE3Hasher()
hasher.update(data1)
let hash1 = hasher.finalize()

hasher.reset()
hasher.update(data2)
let hash2 = hasher.finalize()
```

## API Reference

### `BLAKE3Hasher`

| Method | Description |
|--------|-------------|
| `init()` | Standard hash mode |
| `init(key: [UInt8])` | Keyed hash mode (key must be 32 bytes) |
| `init(derivingKeyFromContext: String)` | Key derivation mode |
| `update(_ input: [UInt8])` | Feed input data (can be called repeatedly) |
| `finalize() -> [UInt8]` | Produce 32-byte hash |
| `finalize(outputLength: Int) -> [UInt8]` | Produce variable-length output |
| `finalize(seek: UInt64, outputLength: Int) -> [UInt8]` | Produce output at an offset |
| `reset()` | Reset to initial state (retains mode and key) |

### `blake3Hash(_ input: [UInt8]) -> [UInt8]`

Convenience function that hashes input in one call and returns a 32-byte digest.

## Project Structure

Each source file corresponds to a file in the original C implementation:

| Swift file | C origin | Purpose |
|------------|----------|---------|
| `Constants.swift` | `blake3_impl.h` | IV, message schedule, flags, utility functions |
| `Portable.swift` | `blake3_portable.c` | Portable compression and hashing |
| `SIMD.swift` | `blake3_neon.c` | SIMD4-parallel 4-way hashing |
| `Dispatch.swift` | `blake3_dispatch.c` | Platform dispatch (SIMD vs portable) |
| `BLAKE3.swift` | `blake3.c` + `blake3.h` | Hasher, chunk state, subtree compression, public API |

## Platform Optimizations

On **arm64** (Apple Silicon), `SIMD4<UInt32>` operations compile to ARM NEON instructions, giving 4-way parallel chunk hashing identical to the C `blake3_neon.c` implementation.

On **x86_64** (Intel Mac), `SIMD4<UInt32>` compiles to SSE instructions, providing the same 4-way parallelism.

On other architectures, the implementation falls back to a portable scalar path.

The single-block compression function always uses the portable path, consistent with the upstream C implementation where NEON does not accelerate single-block compression.

## Testing

```sh
swift test
```

The test suite verifies all three modes (hash, keyed hash, derive key) across 30 official test vectors covering input sizes from 0 to 102,400 bytes, with both default (32-byte) and extended (131-byte) output. Additional tests cover incremental updates, reset, seeking, and the convenience function.
