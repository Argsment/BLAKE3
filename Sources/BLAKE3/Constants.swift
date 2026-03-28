//
//  Constants.swift
//  BLAKE3
//
//  Created by Argsment Limited on 3/28/26.
//

// BLAKE3 initialization vector (same as SHA-256)
let blake3IV: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
]

// Pre-computed message schedule for 7 rounds.
// Each row is one round's permutation of 16 message word indices.
let blake3MsgSchedule: [[Int]] = [
    [ 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15],
    [ 2,  6,  3, 10,  7,  0,  4, 13,  1, 11, 12,  5,  9, 14, 15,  8],
    [ 3,  4, 10, 12, 13,  2,  7, 14,  6,  5,  9,  0, 11, 15,  8,  1],
    [10,  7, 12,  9, 14,  3, 13, 15,  4,  0, 11,  2,  5,  8,  1,  6],
    [12, 13,  9, 11, 15, 10, 14,  8,  7,  2,  5,  3,  0,  1,  6,  4],
    [ 9, 14, 11,  5,  8, 12, 15,  1, 13,  3,  0, 10,  2,  6,  4,  7],
    [11, 15,  5,  0,  1,  9,  8,  6, 14, 10,  2, 12,  3,  4,  7, 13],
]

// Domain separation flags
let CHUNK_START: UInt8         = 1 << 0
let CHUNK_END: UInt8           = 1 << 1
let PARENT: UInt8              = 1 << 2
let ROOT: UInt8                = 1 << 3
let KEYED_HASH: UInt8          = 1 << 4
let DERIVE_KEY_CONTEXT: UInt8  = 1 << 5
let DERIVE_KEY_MATERIAL: UInt8 = 1 << 6

// Size constants
let BLAKE3_KEY_LEN   = 32
let BLAKE3_OUT_LEN   = 32
let BLAKE3_BLOCK_LEN = 64
let BLAKE3_CHUNK_LEN = 1024
let BLAKE3_MAX_DEPTH = 54

#if arch(arm64) || arch(x86_64)
let MAX_SIMD_DEGREE = 4
#else
let MAX_SIMD_DEGREE = 1
#endif
let MAX_SIMD_DEGREE_OR_2 = max(MAX_SIMD_DEGREE, 2)

// MARK: - UInt32 rotation

extension UInt32 {
    @inline(__always)
    func rotated(right amount: Int) -> UInt32 {
        (self >> amount) | (self << (32 - amount))
    }
}

// MARK: - Little-endian load/store

@inline(__always)
func load32(_ ptr: UnsafePointer<UInt8>) -> UInt32 {
    UInt32(littleEndian: UnsafeRawPointer(ptr).loadUnaligned(as: UInt32.self))
}

@inline(__always)
func store32(_ dst: UnsafeMutablePointer<UInt8>, _ value: UInt32) {
    UnsafeMutableRawPointer(dst).storeBytes(of: value.littleEndian, as: UInt32.self)
}

func loadKeyWords(_ key: UnsafePointer<UInt8>) -> [UInt32] {
    var words = [UInt32](repeating: 0, count: 8)
    for i in 0..<8 {
        words[i] = load32(key + i * 4)
    }
    return words
}

func storeCVWords(_ out: UnsafeMutablePointer<UInt8>, _ cv: [UInt32]) {
    for i in 0..<8 {
        store32(out + i * 4, cv[i])
    }
}

// MARK: - Counter helpers

@inline(__always)
func counterLow(_ counter: UInt64) -> UInt32 { UInt32(truncatingIfNeeded: counter) }

@inline(__always)
func counterHigh(_ counter: UInt64) -> UInt32 { UInt32(truncatingIfNeeded: counter >> 32) }

// MARK: - Bit manipulation

func highestOne(_ x: UInt64) -> Int {
    63 - x.leadingZeroBitCount
}

@inline(__always)
func roundDownToPowerOf2(_ x: UInt64) -> UInt64 {
    1 << highestOne(x | 1)
}

@inline(__always)
func popcnt(_ x: UInt64) -> Int {
    x.nonzeroBitCount
}

// MARK: - Byte/word conversion helpers

func wordsToBytes(_ words: [UInt32]) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: words.count * 4)
    for i in 0..<words.count {
        bytes[i * 4]     = UInt8(truncatingIfNeeded: words[i])
        bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: words[i] >> 8)
        bytes[i * 4 + 2] = UInt8(truncatingIfNeeded: words[i] >> 16)
        bytes[i * 4 + 3] = UInt8(truncatingIfNeeded: words[i] >> 24)
    }
    return bytes
}

func bytesToWords(_ bytes: [UInt8]) -> [UInt32] {
    var words = [UInt32](repeating: 0, count: bytes.count / 4)
    for i in 0..<words.count {
        words[i] = UInt32(bytes[i * 4])
                 | (UInt32(bytes[i * 4 + 1]) << 8)
                 | (UInt32(bytes[i * 4 + 2]) << 16)
                 | (UInt32(bytes[i * 4 + 3]) << 24)
    }
    return words
}
