//
//  Portable.swift
//  BLAKE3
//
//  Created by Argsment Limited on 3/28/26.
//

// MARK: - G mixing function

@inline(__always)
func g(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int,
       _ mx: UInt32, _ my: UInt32) {
    state[a] = state[a] &+ state[b] &+ mx
    state[d] = (state[d] ^ state[a]).rotated(right: 16)
    state[c] = state[c] &+ state[d]
    state[b] = (state[b] ^ state[c]).rotated(right: 12)
    state[a] = state[a] &+ state[b] &+ my
    state[d] = (state[d] ^ state[a]).rotated(right: 8)
    state[c] = state[c] &+ state[d]
    state[b] = (state[b] ^ state[c]).rotated(right: 7)
}

// MARK: - Round function (uses pre-computed message schedule)

@inline(__always)
func roundFn(_ state: inout [UInt32], _ msg: [UInt32], _ round: Int) {
    let s = blake3MsgSchedule[round]
    // Mix columns
    g(&state, 0, 4,  8, 12, msg[s[ 0]], msg[s[ 1]])
    g(&state, 1, 5,  9, 13, msg[s[ 2]], msg[s[ 3]])
    g(&state, 2, 6, 10, 14, msg[s[ 4]], msg[s[ 5]])
    g(&state, 3, 7, 11, 15, msg[s[ 6]], msg[s[ 7]])
    // Mix diagonals
    g(&state, 0, 5, 10, 15, msg[s[ 8]], msg[s[ 9]])
    g(&state, 1, 6, 11, 12, msg[s[10]], msg[s[11]])
    g(&state, 2, 7,  8, 13, msg[s[12]], msg[s[13]])
    g(&state, 3, 4,  9, 14, msg[s[14]], msg[s[15]])
}

// MARK: - Core compression (pre-XOR state)

@inline(__always)
func compressPre(_ cv: [UInt32], _ block: UnsafePointer<UInt8>,
                 _ blockLen: UInt8, _ counter: UInt64, _ flags: UInt8) -> [UInt32] {
    var blockWords = [UInt32](repeating: 0, count: 16)
    for i in 0..<16 {
        blockWords[i] = load32(block + i * 4)
    }

    var state: [UInt32] = [
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        blake3IV[0], blake3IV[1], blake3IV[2], blake3IV[3],
        counterLow(counter), counterHigh(counter), UInt32(blockLen), UInt32(flags),
    ]

    roundFn(&state, blockWords, 0)
    roundFn(&state, blockWords, 1)
    roundFn(&state, blockWords, 2)
    roundFn(&state, blockWords, 3)
    roundFn(&state, blockWords, 4)
    roundFn(&state, blockWords, 5)
    roundFn(&state, blockWords, 6)

    return state
}

// MARK: - Compress in place (returns 8-word chaining value)

func compressPortable(cv: [UInt32], block: UnsafePointer<UInt8>,
                      blockLen: UInt8, counter: UInt64, flags: UInt8) -> [UInt32] {
    let state = compressPre(cv, block, blockLen, counter, flags)
    return [
        state[0] ^ state[8],  state[1] ^ state[9],
        state[2] ^ state[10], state[3] ^ state[11],
        state[4] ^ state[12], state[5] ^ state[13],
        state[6] ^ state[14], state[7] ^ state[15],
    ]
}

// MARK: - Compress XOF (returns 64 bytes)

func compressXofPortable(cv: [UInt32], block: UnsafePointer<UInt8>,
                         blockLen: UInt8, counter: UInt64, flags: UInt8,
                         out: UnsafeMutablePointer<UInt8>) {
    let state = compressPre(cv, block, blockLen, counter, flags)
    for i in 0..<8 {
        store32(out + i * 4, state[i] ^ state[i + 8])
    }
    for i in 0..<8 {
        store32(out + (i + 8) * 4, state[i + 8] ^ cv[i])
    }
}

// MARK: - Hash one input (multiple blocks)

func hashOnePortable(input: UnsafePointer<UInt8>, blocks: Int, key: [UInt32],
                     counter: UInt64, flags: UInt8, flagsStart: UInt8,
                     flagsEnd: UInt8, out: UnsafeMutablePointer<UInt8>) {
    var cv = key
    var blockFlags = flags | flagsStart
    var inputPtr = input
    for b in 0..<blocks {
        if b + 1 == blocks { blockFlags |= flagsEnd }
        cv = compressPortable(cv: cv, block: inputPtr, blockLen: UInt8(BLAKE3_BLOCK_LEN),
                              counter: counter, flags: blockFlags)
        inputPtr += BLAKE3_BLOCK_LEN
        blockFlags = flags
    }
    storeCVWords(out, cv)
}

// MARK: - Hash many inputs (portable, sequential)

func hashManyPortable(inputs: UnsafePointer<UnsafePointer<UInt8>>, numInputs: Int,
                      blocks: Int, key: UnsafePointer<UInt32>, counter: UInt64,
                      incrementCounter: Bool, flags: UInt8, flagsStart: UInt8,
                      flagsEnd: UInt8, out: UnsafeMutablePointer<UInt8>) {
    let keyArray = Array(UnsafeBufferPointer(start: key, count: 8))
    var counter = counter
    var outPtr = out
    for i in 0..<numInputs {
        hashOnePortable(input: inputs[i], blocks: blocks, key: keyArray,
                        counter: counter, flags: flags, flagsStart: flagsStart,
                        flagsEnd: flagsEnd, out: outPtr)
        if incrementCounter { counter &+= 1 }
        outPtr += BLAKE3_OUT_LEN
    }
}
