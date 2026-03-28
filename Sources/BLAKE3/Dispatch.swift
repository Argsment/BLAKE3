//
//  Dispatch.swift
//  BLAKE3
//
//  Created by Argsment Limited on 3/28/26.
//

// MARK: - Compression dispatch

@inline(__always)
func compress(cv: [UInt32], block: UnsafePointer<UInt8>, blockLen: UInt8,
              counter: UInt64, flags: UInt8) -> [UInt32] {
    compressPortable(cv: cv, block: block, blockLen: blockLen,
                     counter: counter, flags: flags)
}

@inline(__always)
func compressXof(cv: [UInt32], block: UnsafePointer<UInt8>, blockLen: UInt8,
                 counter: UInt64, flags: UInt8,
                 out: UnsafeMutablePointer<UInt8>) {
    compressXofPortable(cv: cv, block: block, blockLen: blockLen,
                        counter: counter, flags: flags, out: out)
}

// MARK: - XOF many (loop of compress_xof with incrementing counter)

func xofMany(cv: [UInt32], block: UnsafePointer<UInt8>, blockLen: UInt8,
             counter: UInt64, flags: UInt8,
             out: UnsafeMutablePointer<UInt8>, outBlocks: Int) {
    for i in 0..<outBlocks {
        compressXof(cv: cv, block: block, blockLen: blockLen,
                    counter: counter &+ UInt64(i), flags: flags,
                    out: out + i * 64)
    }
}

// MARK: - Hash many dispatch

func hashMany(inputs: UnsafePointer<UnsafePointer<UInt8>>, numInputs: Int,
              blocks: Int, key: UnsafePointer<UInt32>, counter: UInt64,
              incrementCounter: Bool, flags: UInt8, flagsStart: UInt8,
              flagsEnd: UInt8, out: UnsafeMutablePointer<UInt8>) {
    #if arch(arm64) || arch(x86_64)
    hashManySIMD(inputs: inputs, numInputs: numInputs, blocks: blocks, key: key,
                 counter: counter, incrementCounter: incrementCounter, flags: flags,
                 flagsStart: flagsStart, flagsEnd: flagsEnd, out: out)
    #else
    hashManyPortable(inputs: inputs, numInputs: numInputs, blocks: blocks, key: key,
                     counter: counter, incrementCounter: incrementCounter, flags: flags,
                     flagsStart: flagsStart, flagsEnd: flagsEnd, out: out)
    #endif
}

// MARK: - SIMD degree

func simdDegree() -> Int {
    #if arch(arm64) || arch(x86_64)
    return 4
    #else
    return 1
    #endif
}
