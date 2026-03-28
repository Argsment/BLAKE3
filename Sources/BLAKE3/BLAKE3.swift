//
//  BLAKE3.swift
//  BLAKE3
//
//  Created by Argsment Limited on 3/28/26.
//

// MARK: - Output (captures state needed for finalization)

struct Output {
    var inputCV: [UInt32]   // 8 elements
    var counter: UInt64
    var block: [UInt8]      // BLAKE3_BLOCK_LEN bytes
    var blockLen: UInt8
    var flags: UInt8

    func chainingValue() -> [UInt8] {
        let localBlock = self.block
        let cvWords: [UInt32] = localBlock.withUnsafeBufferPointer { blockPtr in
            compress(cv: self.inputCV, block: blockPtr.baseAddress!,
                     blockLen: self.blockLen, counter: self.counter, flags: self.flags)
        }
        return wordsToBytes(cvWords)
    }

    func rootOutputBytes(seek: UInt64, outputLength: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: outputLength)
        if outputLength == 0 { return out }

        let localBlock = self.block
        let localCV = self.inputCV
        let localBlockLen = self.blockLen
        let localFlags = self.flags | ROOT

        localBlock.withUnsafeBufferPointer { blockPtr in
            let block = blockPtr.baseAddress!
            var outputBlockCounter = seek / 64
            var offsetWithinBlock = Int(seek % 64)
            var outPos = 0

            // Handle partial first block (when seeking into the middle)
            if offsetWithinBlock != 0 {
                var wideBuf = [UInt8](repeating: 0, count: 64)
                wideBuf.withUnsafeMutableBufferPointer { wBuf in
                    compressXof(cv: localCV, block: block, blockLen: localBlockLen,
                                counter: outputBlockCounter, flags: localFlags,
                                out: wBuf.baseAddress!)
                }
                let available = 64 - offsetWithinBlock
                let take = min(available, outputLength)
                for i in 0..<take { out[outPos + i] = wideBuf[offsetWithinBlock + i] }
                outPos += take
                outputBlockCounter += 1
                offsetWithinBlock = 0
            }

            // Handle full 64-byte blocks
            let fullBlocks = (outputLength - outPos) / 64
            if fullBlocks > 0 {
                out.withUnsafeMutableBufferPointer { outBuf in
                    xofMany(cv: localCV, block: block, blockLen: localBlockLen,
                            counter: outputBlockCounter, flags: localFlags,
                            out: outBuf.baseAddress! + outPos, outBlocks: fullBlocks)
                }
                outPos += fullBlocks * 64
                outputBlockCounter += UInt64(fullBlocks)
            }

            // Handle trailing partial block
            if outPos < outputLength {
                var wideBuf = [UInt8](repeating: 0, count: 64)
                wideBuf.withUnsafeMutableBufferPointer { wBuf in
                    compressXof(cv: localCV, block: block, blockLen: localBlockLen,
                                counter: outputBlockCounter, flags: localFlags,
                                out: wBuf.baseAddress!)
                }
                let remaining = outputLength - outPos
                for i in 0..<remaining { out[outPos + i] = wideBuf[i] }
            }
        }

        return out
    }
}

// MARK: - ChunkState

struct ChunkState {
    var cv: [UInt32]
    var chunkCounter: UInt64
    var block: [UInt8]
    var blockLen: UInt8
    var blocksCompressed: UInt8
    var flags: UInt8

    init(key: [UInt32], chunkCounter: UInt64, flags: UInt8) {
        self.cv = key
        self.chunkCounter = chunkCounter
        self.block = [UInt8](repeating: 0, count: BLAKE3_BLOCK_LEN)
        self.blockLen = 0
        self.blocksCompressed = 0
        self.flags = flags
    }

    var len: Int {
        BLAKE3_BLOCK_LEN * Int(blocksCompressed) + Int(blockLen)
    }

    var startFlag: UInt8 {
        blocksCompressed == 0 ? CHUNK_START : 0
    }

    mutating func update(from ptr: UnsafePointer<UInt8>, count: Int) {
        var inputPtr = ptr
        var remaining = count

        // If buffer has data, fill it first
        if blockLen > 0 {
            let take = min(BLAKE3_BLOCK_LEN - Int(blockLen), remaining)
            for i in 0..<take {
                block[Int(blockLen) + i] = inputPtr[i]
            }
            blockLen += UInt8(take)
            inputPtr += take
            remaining -= take
            if remaining > 0 {
                // Block full, compress it
                let localBlock = self.block
                let localCV = self.cv
                let counter = self.chunkCounter
                let blockFlags = self.flags | self.startFlag
                self.cv = localBlock.withUnsafeBufferPointer { bPtr in
                    compress(cv: localCV, block: bPtr.baseAddress!,
                             blockLen: UInt8(BLAKE3_BLOCK_LEN),
                             counter: counter, flags: blockFlags)
                }
                blocksCompressed += 1
                block = [UInt8](repeating: 0, count: BLAKE3_BLOCK_LEN)
                blockLen = 0
            }
        }

        // Compress full blocks directly from input
        while remaining > BLAKE3_BLOCK_LEN {
            let localCV = self.cv
            let counter = self.chunkCounter
            let blockFlags = self.flags | self.startFlag
            self.cv = compress(cv: localCV, block: inputPtr,
                               blockLen: UInt8(BLAKE3_BLOCK_LEN),
                               counter: counter, flags: blockFlags)
            blocksCompressed += 1
            inputPtr += BLAKE3_BLOCK_LEN
            remaining -= BLAKE3_BLOCK_LEN
        }

        // Buffer remaining bytes
        if remaining > 0 {
            for i in 0..<remaining {
                block[Int(blockLen) + i] = inputPtr[i]
            }
            blockLen += UInt8(remaining)
        }
    }

    func output() -> Output {
        Output(inputCV: cv, counter: chunkCounter, block: block,
               blockLen: blockLen,
               flags: flags | startFlag | CHUNK_END)
    }
}

// MARK: - Parent node helpers

func parentOutput(_ block: [UInt8], _ key: [UInt32], _ flags: UInt8) -> Output {
    Output(inputCV: key, counter: 0, block: block,
           blockLen: UInt8(BLAKE3_BLOCK_LEN), flags: flags | PARENT)
}

func parentCV(_ block: [UInt8], _ key: [UInt32], _ flags: UInt8) -> [UInt8] {
    parentOutput(block, key, flags).chainingValue()
}

// MARK: - SIMD-parallel subtree compression

func leftSubtreeLen(_ inputLen: Int) -> Int {
    let fullChunks = (inputLen - 1) / BLAKE3_CHUNK_LEN
    return Int(roundDownToPowerOf2(UInt64(fullChunks))) * BLAKE3_CHUNK_LEN
}

func compressChunksParallel(input: UnsafePointer<UInt8>, inputLen: Int,
                            key: [UInt32], chunkCounter: UInt64,
                            flags: UInt8,
                            out: UnsafeMutablePointer<UInt8>) -> Int {
    var chunksArray = [UnsafePointer<UInt8>]()
    chunksArray.reserveCapacity(MAX_SIMD_DEGREE)
    var pos = 0
    while inputLen - pos >= BLAKE3_CHUNK_LEN {
        chunksArray.append(input.advanced(by: pos))
        pos += BLAKE3_CHUNK_LEN
    }

    key.withUnsafeBufferPointer { keyBuf in
        chunksArray.withUnsafeBufferPointer { chunksBuf in
            hashMany(inputs: chunksBuf.baseAddress!, numInputs: chunksArray.count,
                     blocks: BLAKE3_CHUNK_LEN / BLAKE3_BLOCK_LEN,
                     key: keyBuf.baseAddress!, counter: chunkCounter,
                     incrementCounter: true, flags: flags,
                     flagsStart: CHUNK_START, flagsEnd: CHUNK_END, out: out)
        }
    }

    // Handle remaining partial chunk
    if inputLen > pos {
        let counter = chunkCounter + UInt64(chunksArray.count)
        var chunkState = ChunkState(key: key, chunkCounter: counter, flags: flags)
        chunkState.update(from: input.advanced(by: pos), count: inputLen - pos)
        let cv = chunkState.output().chainingValue()
        cv.withUnsafeBufferPointer { cvBuf in
            UnsafeMutableRawPointer(out + chunksArray.count * BLAKE3_OUT_LEN)
                .copyMemory(from: UnsafeRawPointer(cvBuf.baseAddress!),
                            byteCount: BLAKE3_OUT_LEN)
        }
        return chunksArray.count + 1
    }
    return chunksArray.count
}

func compressParentsParallel(childCVs: UnsafePointer<UInt8>, numCVs: Int,
                             key: [UInt32], flags: UInt8,
                             out: UnsafeMutablePointer<UInt8>) -> Int {
    var parentsArray = [UnsafePointer<UInt8>]()
    parentsArray.reserveCapacity(MAX_SIMD_DEGREE_OR_2)
    var i = 0
    while numCVs - 2 * i >= 2 {
        parentsArray.append(childCVs.advanced(by: 2 * i * BLAKE3_OUT_LEN))
        i += 1
    }

    key.withUnsafeBufferPointer { keyBuf in
        parentsArray.withUnsafeBufferPointer { parentsBuf in
            hashMany(inputs: parentsBuf.baseAddress!, numInputs: parentsArray.count,
                     blocks: 1, key: keyBuf.baseAddress!, counter: 0,
                     incrementCounter: false, flags: flags | PARENT,
                     flagsStart: 0, flagsEnd: 0, out: out)
        }
    }

    // If there's an odd child left over, pass it through
    if numCVs > 2 * parentsArray.count {
        UnsafeMutableRawPointer(out + parentsArray.count * BLAKE3_OUT_LEN)
            .copyMemory(from: UnsafeRawPointer(childCVs + 2 * parentsArray.count * BLAKE3_OUT_LEN),
                        byteCount: BLAKE3_OUT_LEN)
        return parentsArray.count + 1
    }
    return parentsArray.count
}

func compressSubtreeWide(input: UnsafePointer<UInt8>, inputLen: Int,
                         key: [UInt32], chunkCounter: UInt64,
                         flags: UInt8,
                         out: UnsafeMutablePointer<UInt8>) -> Int {
    if inputLen <= simdDegree() * BLAKE3_CHUNK_LEN {
        return compressChunksParallel(input: input, inputLen: inputLen, key: key,
                                      chunkCounter: chunkCounter, flags: flags,
                                      out: out)
    }

    let leftLen = leftSubtreeLen(inputLen)
    let rightLen = inputLen - leftLen
    let rightInput = input.advanced(by: leftLen)
    let rightChunkCounter = chunkCounter + UInt64(leftLen / BLAKE3_CHUNK_LEN)

    var degree = simdDegree()
    if leftLen > BLAKE3_CHUNK_LEN && degree == 1 {
        degree = 2
    }

    let cvArraySize = 2 * MAX_SIMD_DEGREE_OR_2 * BLAKE3_OUT_LEN
    var cvArray = [UInt8](repeating: 0, count: cvArraySize)

    return cvArray.withUnsafeMutableBufferPointer { cvBuf in
        let cvPtr = cvBuf.baseAddress!
        let rightCVs = cvPtr.advanced(by: degree * BLAKE3_OUT_LEN)

        let leftN = compressSubtreeWide(input: input, inputLen: leftLen, key: key,
                                         chunkCounter: chunkCounter, flags: flags,
                                         out: cvPtr)
        let rightN = compressSubtreeWide(input: rightInput, inputLen: rightLen,
                                          key: key, chunkCounter: rightChunkCounter,
                                          flags: flags, out: rightCVs)

        if leftN == 1 {
            UnsafeMutableRawPointer(out).copyMemory(from: UnsafeRawPointer(cvPtr),
                                                     byteCount: 2 * BLAKE3_OUT_LEN)
            return 2
        }

        let numCVs = leftN + rightN
        return compressParentsParallel(childCVs: cvPtr, numCVs: numCVs, key: key,
                                       flags: flags, out: out)
    }
}

func compressSubtreeToParentNode(input: UnsafePointer<UInt8>, inputLen: Int,
                                 key: [UInt32], chunkCounter: UInt64,
                                 flags: UInt8,
                                 out: UnsafeMutablePointer<UInt8>) {
    let cvArraySize = MAX_SIMD_DEGREE_OR_2 * BLAKE3_OUT_LEN
    var cvArray = [UInt8](repeating: 0, count: cvArraySize)

    cvArray.withUnsafeMutableBufferPointer { cvBuf in
        let cvPtr = cvBuf.baseAddress!
        var numCVs = compressSubtreeWide(input: input, inputLen: inputLen, key: key,
                                          chunkCounter: chunkCounter, flags: flags,
                                          out: cvPtr)

        var outArray = [UInt8](repeating: 0, count: cvArraySize)
        outArray.withUnsafeMutableBufferPointer { outBuf in
            let outPtr = outBuf.baseAddress!
            while numCVs > 2 {
                numCVs = compressParentsParallel(childCVs: cvPtr, numCVs: numCVs,
                                                  key: key, flags: flags, out: outPtr)
                UnsafeMutableRawPointer(cvPtr).copyMemory(
                    from: UnsafeRawPointer(outPtr),
                    byteCount: numCVs * BLAKE3_OUT_LEN)
            }
        }

        UnsafeMutableRawPointer(out).copyMemory(from: UnsafeRawPointer(cvPtr),
                                                 byteCount: 2 * BLAKE3_OUT_LEN)
    }
}

// MARK: - Public BLAKE3Hasher

public struct BLAKE3Hasher {
    var key: [UInt32]
    var chunk: ChunkState
    var cvStackLen: UInt8
    var cvStack: [UInt8]

    // MARK: Initialization

    init(keyWords: [UInt32], flags: UInt8) {
        self.key = keyWords
        self.chunk = ChunkState(key: keyWords, chunkCounter: 0, flags: flags)
        self.cvStackLen = 0
        self.cvStack = [UInt8](repeating: 0, count: (BLAKE3_MAX_DEPTH + 1) * BLAKE3_OUT_LEN)
    }

    public init() {
        self.init(keyWords: blake3IV, flags: 0)
    }

    public init(key: [UInt8]) {
        precondition(key.count == BLAKE3_KEY_LEN, "BLAKE3 key must be exactly 32 bytes")
        let keyWords = bytesToWords(key)
        self.init(keyWords: keyWords, flags: KEYED_HASH)
    }

    public init(derivingKeyFromContext context: String) {
        var contextHasher = BLAKE3Hasher(keyWords: blake3IV, flags: DERIVE_KEY_CONTEXT)
        contextHasher.update(Array(context.utf8))
        let contextKey = contextHasher.finalize(outputLength: BLAKE3_KEY_LEN)
        let contextKeyWords = bytesToWords(contextKey)
        self.init(keyWords: contextKeyWords, flags: DERIVE_KEY_MATERIAL)
    }

    // MARK: CV stack management (lazy merging)

    private mutating func mergeCVStack(totalLen: UInt64) {
        let postMergeStackLen = popcnt(totalLen)
        while Int(cvStackLen) > postMergeStackLen {
            let parentOffset = (Int(cvStackLen) - 2) * BLAKE3_OUT_LEN
            let parentBlock = Array(cvStack[parentOffset ..< parentOffset + BLAKE3_BLOCK_LEN])
            let output = parentOutput(parentBlock, key, chunk.flags)
            let cv = output.chainingValue()
            for i in 0..<BLAKE3_OUT_LEN {
                cvStack[parentOffset + i] = cv[i]
            }
            cvStackLen -= 1
        }
    }

    private mutating func pushCV(_ newCV: [UInt8], chunkCounter: UInt64) {
        mergeCVStack(totalLen: chunkCounter)
        let offset = Int(cvStackLen) * BLAKE3_OUT_LEN
        for i in 0..<BLAKE3_OUT_LEN {
            cvStack[offset + i] = newCV[i]
        }
        cvStackLen += 1
    }

    // MARK: Update

    public mutating func update(_ input: [UInt8]) {
        if input.isEmpty { return }

        input.withUnsafeBufferPointer { inputBuf in
            var inputPtr = inputBuf.baseAddress!
            var inputLen = input.count

            // Fill partial chunk first
            if chunk.len > 0 {
                let take = min(BLAKE3_CHUNK_LEN - chunk.len, inputLen)
                chunk.update(from: inputPtr, count: take)
                inputPtr += take
                inputLen -= take
                if inputLen > 0 {
                    let chunkCV = chunk.output().chainingValue()
                    pushCV(chunkCV, chunkCounter: chunk.chunkCounter)
                    chunk = ChunkState(key: key, chunkCounter: chunk.chunkCounter + 1,
                                       flags: chunk.flags)
                } else {
                    return
                }
            }

            // Process large subtrees with SIMD parallelism
            while inputLen > BLAKE3_CHUNK_LEN {
                var subtreeLen = Int(roundDownToPowerOf2(UInt64(inputLen)))
                let countSoFar = chunk.chunkCounter &* UInt64(BLAKE3_CHUNK_LEN)
                while (UInt64(subtreeLen - 1) & countSoFar) != 0 {
                    subtreeLen /= 2
                }
                let subtreeChunks = subtreeLen / BLAKE3_CHUNK_LEN

                if subtreeLen <= BLAKE3_CHUNK_LEN {
                    var cs = ChunkState(key: key, chunkCounter: chunk.chunkCounter,
                                        flags: chunk.flags)
                    cs.update(from: inputPtr, count: subtreeLen)
                    let cv = cs.output().chainingValue()
                    pushCV(cv, chunkCounter: cs.chunkCounter)
                } else {
                    var cvPair = [UInt8](repeating: 0, count: 2 * BLAKE3_OUT_LEN)
                    cvPair.withUnsafeMutableBufferPointer { cvBuf in
                        compressSubtreeToParentNode(
                            input: inputPtr, inputLen: subtreeLen, key: key,
                            chunkCounter: chunk.chunkCounter, flags: chunk.flags,
                            out: cvBuf.baseAddress!)
                    }
                    pushCV(Array(cvPair[0 ..< BLAKE3_OUT_LEN]),
                           chunkCounter: chunk.chunkCounter)
                    pushCV(Array(cvPair[BLAKE3_OUT_LEN ..< 2 * BLAKE3_OUT_LEN]),
                           chunkCounter: chunk.chunkCounter + UInt64(subtreeChunks / 2))
                }

                chunk.chunkCounter += UInt64(subtreeChunks)
                inputPtr += subtreeLen
                inputLen -= subtreeLen
            }

            // Process remaining input (< 1 chunk)
            if inputLen > 0 {
                chunk.update(from: inputPtr, count: inputLen)
                mergeCVStack(totalLen: chunk.chunkCounter)
            }
        }
    }

    // MARK: Finalize

    public func finalize() -> [UInt8] {
        finalize(seek: 0, outputLength: BLAKE3_OUT_LEN)
    }

    public func finalize(outputLength: Int) -> [UInt8] {
        finalize(seek: 0, outputLength: outputLength)
    }

    public func finalize(seek: UInt64, outputLength: Int) -> [UInt8] {
        if outputLength == 0 { return [] }

        // If the stack is empty, the current chunk is the root
        if cvStackLen == 0 {
            return chunk.output().rootOutputBytes(seek: seek, outputLength: outputLength)
        }

        // Build the final output by merging the CV stack
        var output: Output
        var cvsRemaining: Int

        if chunk.len > 0 {
            cvsRemaining = Int(cvStackLen)
            output = chunk.output()
        } else {
            cvsRemaining = Int(cvStackLen) - 2
            let parentBlock = Array(cvStack[cvsRemaining * BLAKE3_OUT_LEN ..< cvsRemaining * BLAKE3_OUT_LEN + BLAKE3_BLOCK_LEN])
            output = parentOutput(parentBlock, key, chunk.flags)
        }

        while cvsRemaining > 0 {
            cvsRemaining -= 1
            let leftCV = Array(cvStack[cvsRemaining * BLAKE3_OUT_LEN ..< (cvsRemaining + 1) * BLAKE3_OUT_LEN])
            let rightCV = output.chainingValue()
            var parentBlock = [UInt8](repeating: 0, count: BLAKE3_BLOCK_LEN)
            for i in 0..<BLAKE3_OUT_LEN { parentBlock[i] = leftCV[i] }
            for i in 0..<BLAKE3_OUT_LEN { parentBlock[BLAKE3_OUT_LEN + i] = rightCV[i] }
            output = parentOutput(parentBlock, key, chunk.flags)
        }

        return output.rootOutputBytes(seek: seek, outputLength: outputLength)
    }

    // MARK: Reset

    public mutating func reset() {
        chunk = ChunkState(key: key, chunkCounter: 0, flags: chunk.flags)
        cvStackLen = 0
    }
}

// MARK: - Convenience functions

public func blake3Hash(_ input: [UInt8]) -> [UInt8] {
    var hasher = BLAKE3Hasher()
    hasher.update(input)
    return hasher.finalize()
}
