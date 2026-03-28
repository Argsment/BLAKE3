//
//  SIMD.swift
//  BLAKE3
//
//  Created by Argsment Limited on 3/28/26.
//

#if arch(arm64) || arch(x86_64)

// MARK: - SIMD4 rotation helpers

private let _s7  = SIMD4<UInt32>(repeating: 7)
private let _s8  = SIMD4<UInt32>(repeating: 8)
private let _s12 = SIMD4<UInt32>(repeating: 12)
private let _s16 = SIMD4<UInt32>(repeating: 16)
private let _s20 = SIMD4<UInt32>(repeating: 20)
private let _s24 = SIMD4<UInt32>(repeating: 24)
private let _s25 = SIMD4<UInt32>(repeating: 25)

@inline(__always)
func rotR16(_ x: SIMD4<UInt32>) -> SIMD4<UInt32> { (x &>> _s16) | (x &<< _s16) }

@inline(__always)
func rotR12(_ x: SIMD4<UInt32>) -> SIMD4<UInt32> { (x &>> _s12) | (x &<< _s20) }

@inline(__always)
func rotR8(_ x: SIMD4<UInt32>) -> SIMD4<UInt32> { (x &>> _s8) | (x &<< _s24) }

@inline(__always)
func rotR7(_ x: SIMD4<UInt32>) -> SIMD4<UInt32> { (x &>> _s7) | (x &<< _s25) }

// MARK: - 4-way parallel round function

@inline(__always)
func roundFn4(_ v: inout [SIMD4<UInt32>], _ m: [SIMD4<UInt32>], _ round: Int) {
    let s = blake3MsgSchedule[round]

    // Column step
    v[0] = v[0] &+ m[s[0]];  v[1] = v[1] &+ m[s[2]]
    v[2] = v[2] &+ m[s[4]];  v[3] = v[3] &+ m[s[6]]
    v[0] = v[0] &+ v[4];     v[1] = v[1] &+ v[5]
    v[2] = v[2] &+ v[6];     v[3] = v[3] &+ v[7]
    v[12] = rotR16(v[12] ^ v[0]); v[13] = rotR16(v[13] ^ v[1])
    v[14] = rotR16(v[14] ^ v[2]); v[15] = rotR16(v[15] ^ v[3])
    v[8]  = v[8]  &+ v[12];  v[9]  = v[9]  &+ v[13]
    v[10] = v[10] &+ v[14];  v[11] = v[11] &+ v[15]
    v[4] = rotR12(v[4] ^ v[8]);   v[5] = rotR12(v[5] ^ v[9])
    v[6] = rotR12(v[6] ^ v[10]);  v[7] = rotR12(v[7] ^ v[11])
    v[0] = v[0] &+ m[s[1]];  v[1] = v[1] &+ m[s[3]]
    v[2] = v[2] &+ m[s[5]];  v[3] = v[3] &+ m[s[7]]
    v[0] = v[0] &+ v[4];     v[1] = v[1] &+ v[5]
    v[2] = v[2] &+ v[6];     v[3] = v[3] &+ v[7]
    v[12] = rotR8(v[12] ^ v[0]);  v[13] = rotR8(v[13] ^ v[1])
    v[14] = rotR8(v[14] ^ v[2]);  v[15] = rotR8(v[15] ^ v[3])
    v[8]  = v[8]  &+ v[12];  v[9]  = v[9]  &+ v[13]
    v[10] = v[10] &+ v[14];  v[11] = v[11] &+ v[15]
    v[4] = rotR7(v[4] ^ v[8]);    v[5] = rotR7(v[5] ^ v[9])
    v[6] = rotR7(v[6] ^ v[10]);   v[7] = rotR7(v[7] ^ v[11])

    // Diagonal step
    v[0] = v[0] &+ m[s[8]];  v[1] = v[1] &+ m[s[10]]
    v[2] = v[2] &+ m[s[12]]; v[3] = v[3] &+ m[s[14]]
    v[0] = v[0] &+ v[5];     v[1] = v[1] &+ v[6]
    v[2] = v[2] &+ v[7];     v[3] = v[3] &+ v[4]
    v[15] = rotR16(v[15] ^ v[0]); v[12] = rotR16(v[12] ^ v[1])
    v[13] = rotR16(v[13] ^ v[2]); v[14] = rotR16(v[14] ^ v[3])
    v[10] = v[10] &+ v[15];  v[11] = v[11] &+ v[12]
    v[8]  = v[8]  &+ v[13];  v[9]  = v[9]  &+ v[14]
    v[5] = rotR12(v[5] ^ v[10]);  v[6] = rotR12(v[6] ^ v[11])
    v[7] = rotR12(v[7] ^ v[8]);   v[4] = rotR12(v[4] ^ v[9])
    v[0] = v[0] &+ m[s[9]];  v[1] = v[1] &+ m[s[11]]
    v[2] = v[2] &+ m[s[13]]; v[3] = v[3] &+ m[s[15]]
    v[0] = v[0] &+ v[5];     v[1] = v[1] &+ v[6]
    v[2] = v[2] &+ v[7];     v[3] = v[3] &+ v[4]
    v[15] = rotR8(v[15] ^ v[0]);  v[12] = rotR8(v[12] ^ v[1])
    v[13] = rotR8(v[13] ^ v[2]);  v[14] = rotR8(v[14] ^ v[3])
    v[10] = v[10] &+ v[15];  v[11] = v[11] &+ v[12]
    v[8]  = v[8]  &+ v[13];  v[9]  = v[9]  &+ v[14]
    v[5] = rotR7(v[5] ^ v[10]);   v[6] = rotR7(v[6] ^ v[11])
    v[7] = rotR7(v[7] ^ v[8]);    v[4] = rotR7(v[4] ^ v[9])
}

// MARK: - 4×4 matrix transpose of SIMD4 vectors

@inline(__always)
func transpose4(_ v: inout [SIMD4<UInt32>], at base: Int) {
    let a = v[base], b = v[base + 1], c = v[base + 2], d = v[base + 3]
    v[base]     = SIMD4(a[0], b[0], c[0], d[0])
    v[base + 1] = SIMD4(a[1], b[1], c[1], d[1])
    v[base + 2] = SIMD4(a[2], b[2], c[2], d[2])
    v[base + 3] = SIMD4(a[3], b[3], c[3], d[3])
}

// MARK: - Load 16 message words from 4 inputs and transpose

@inline(__always)
func loadSIMD4LE(_ ptr: UnsafePointer<UInt8>) -> SIMD4<UInt32> {
    #if _endian(big)
    return SIMD4(load32(ptr), load32(ptr + 4), load32(ptr + 8), load32(ptr + 12))
    #else
    return UnsafeRawPointer(ptr).loadUnaligned(as: SIMD4<UInt32>.self)
    #endif
}

@inline(__always)
func storeSIMD4LE(_ value: SIMD4<UInt32>, to ptr: UnsafeMutablePointer<UInt8>) {
    #if _endian(big)
    store32(ptr,      value[0])
    store32(ptr + 4,  value[1])
    store32(ptr + 8,  value[2])
    store32(ptr + 12, value[3])
    #else
    UnsafeMutableRawPointer(ptr).storeBytes(of: value, as: SIMD4<UInt32>.self)
    #endif
}

func transposeMsgVecs4(_ inputs: UnsafePointer<UnsafePointer<UInt8>>,
                       blockOffset: Int) -> [SIMD4<UInt32>] {
    var out = [SIMD4<UInt32>](repeating: .zero, count: 16)
    for row in 0..<4 {
        for col in 0..<4 {
            out[row * 4 + col] = loadSIMD4LE(inputs[col].advanced(by: blockOffset + row * 16))
        }
    }
    transpose4(&out, at: 0)
    transpose4(&out, at: 4)
    transpose4(&out, at: 8)
    transpose4(&out, at: 12)
    return out
}

// MARK: - Load 4 counters

@inline(__always)
func loadCounters4(counter: UInt64, incrementCounter: Bool)
    -> (low: SIMD4<UInt32>, high: SIMD4<UInt32>)
{
    let mask: UInt64 = incrementCounter ? ~0 : 0
    let low = SIMD4<UInt32>(
        counterLow(counter &+ (mask & 0)),
        counterLow(counter &+ (mask & 1)),
        counterLow(counter &+ (mask & 2)),
        counterLow(counter &+ (mask & 3))
    )
    let high = SIMD4<UInt32>(
        counterHigh(counter &+ (mask & 0)),
        counterHigh(counter &+ (mask & 1)),
        counterHigh(counter &+ (mask & 2)),
        counterHigh(counter &+ (mask & 3))
    )
    return (low, high)
}

// MARK: - Hash 4 inputs in parallel using SIMD4

func hash4SIMD(inputs: UnsafePointer<UnsafePointer<UInt8>>, blocks: Int,
               key: UnsafePointer<UInt32>, counter: UInt64,
               incrementCounter: Bool, flags: UInt8, flagsStart: UInt8,
               flagsEnd: UInt8, out: UnsafeMutablePointer<UInt8>) {
    var hVecs: [SIMD4<UInt32>] = [
        SIMD4(repeating: key[0]), SIMD4(repeating: key[1]),
        SIMD4(repeating: key[2]), SIMD4(repeating: key[3]),
        SIMD4(repeating: key[4]), SIMD4(repeating: key[5]),
        SIMD4(repeating: key[6]), SIMD4(repeating: key[7]),
    ]
    let (counterLowVec, counterHighVec) = loadCounters4(counter: counter,
                                                         incrementCounter: incrementCounter)
    var blockFlags = flags | flagsStart

    for block in 0..<blocks {
        if block + 1 == blocks { blockFlags |= flagsEnd }
        let blockLenVec = SIMD4<UInt32>(repeating: UInt32(BLAKE3_BLOCK_LEN))
        let blockFlagsVec = SIMD4<UInt32>(repeating: UInt32(blockFlags))
        let msgVecs = transposeMsgVecs4(inputs, blockOffset: block * BLAKE3_BLOCK_LEN)

        var v: [SIMD4<UInt32>] = [
            hVecs[0], hVecs[1], hVecs[2], hVecs[3],
            hVecs[4], hVecs[5], hVecs[6], hVecs[7],
            SIMD4(repeating: blake3IV[0]), SIMD4(repeating: blake3IV[1]),
            SIMD4(repeating: blake3IV[2]), SIMD4(repeating: blake3IV[3]),
            counterLowVec, counterHighVec, blockLenVec, blockFlagsVec,
        ]
        roundFn4(&v, msgVecs, 0)
        roundFn4(&v, msgVecs, 1)
        roundFn4(&v, msgVecs, 2)
        roundFn4(&v, msgVecs, 3)
        roundFn4(&v, msgVecs, 4)
        roundFn4(&v, msgVecs, 5)
        roundFn4(&v, msgVecs, 6)

        hVecs[0] = v[0] ^ v[8];  hVecs[1] = v[1] ^ v[9]
        hVecs[2] = v[2] ^ v[10]; hVecs[3] = v[3] ^ v[11]
        hVecs[4] = v[4] ^ v[12]; hVecs[5] = v[5] ^ v[13]
        hVecs[6] = v[6] ^ v[14]; hVecs[7] = v[7] ^ v[15]

        blockFlags = flags
    }

    // Transpose hVecs back and store to output
    transpose4(&hVecs, at: 0)
    transpose4(&hVecs, at: 4)
    // First 4 vecs = first half of each output, second 4 = second half
    storeSIMD4LE(hVecs[0], to: out + 0 * 16)
    storeSIMD4LE(hVecs[4], to: out + 1 * 16)
    storeSIMD4LE(hVecs[1], to: out + 2 * 16)
    storeSIMD4LE(hVecs[5], to: out + 3 * 16)
    storeSIMD4LE(hVecs[2], to: out + 4 * 16)
    storeSIMD4LE(hVecs[6], to: out + 5 * 16)
    storeSIMD4LE(hVecs[3], to: out + 6 * 16)
    storeSIMD4LE(hVecs[7], to: out + 7 * 16)
}

// MARK: - Hash many inputs using SIMD4 + portable fallback

func hashManySIMD(inputs: UnsafePointer<UnsafePointer<UInt8>>, numInputs: Int,
                  blocks: Int, key: UnsafePointer<UInt32>, counter: UInt64,
                  incrementCounter: Bool, flags: UInt8, flagsStart: UInt8,
                  flagsEnd: UInt8, out: UnsafeMutablePointer<UInt8>) {
    var inputsPtr = inputs
    var remaining = numInputs
    var counter = counter
    var outPtr = out

    while remaining >= 4 {
        hash4SIMD(inputs: inputsPtr, blocks: blocks, key: key, counter: counter,
                  incrementCounter: incrementCounter, flags: flags,
                  flagsStart: flagsStart, flagsEnd: flagsEnd, out: outPtr)
        if incrementCounter { counter &+= 4 }
        inputsPtr += 4
        remaining -= 4
        outPtr += 4 * BLAKE3_OUT_LEN
    }

    let keyArray = Array(UnsafeBufferPointer(start: key, count: 8))
    while remaining > 0 {
        hashOnePortable(input: inputsPtr.pointee, blocks: blocks, key: keyArray,
                        counter: counter, flags: flags, flagsStart: flagsStart,
                        flagsEnd: flagsEnd, out: outPtr)
        if incrementCounter { counter &+= 1 }
        inputsPtr += 1
        remaining -= 1
        outPtr += BLAKE3_OUT_LEN
    }
}

#endif // arch(arm64) || arch(x86_64)
