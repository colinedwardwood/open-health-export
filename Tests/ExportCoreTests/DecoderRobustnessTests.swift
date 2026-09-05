import CompanionWire
import Foundation
import MQTTCodec
import Testing
import WireFormat

// R-84: a bounded, seeded fuzz run over the companion and MQTT decoders, plus the
// adversarial inputs worth pinning as named regressions.
//
// The generator below is a deliberate duplicate of the one in `Tools/wirefuzz`.
// `wirefuzz` is an executable target, so it cannot be imported by a test target, and
// hoisting the generator into a library would mean adding a SwiftPM target. The
// PRNG constants, the corpus, and the order of the mutation and generation switches
// are identical to the tool's, so a seed reproduces the same input stream in both.

// MARK: - Duplicated deterministic generator

/// splitmix64, matching `SplitMix64` in `Tools/wirefuzz/WireFuzz.swift`.
struct RobustnessRNG: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func byte() -> UInt8 {
        UInt8(truncatingIfNeeded: next())
    }

    mutating func below(_ upper: Int) -> Int {
        guard upper > 1 else { return 0 }
        return Int(next() % UInt64(upper))
    }

    mutating func inRange(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + below(range.count)
    }

    mutating func bool() -> Bool {
        next() & 1 == 1
    }

    mutating func bytes(count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        for _ in 0..<count { out.append(byte()) }
        return out
    }
}

enum RobustnessBytes {
    static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func hex(_ bytes: [UInt8], limit: Int = 96) -> String {
        let shown = bytes.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
        return bytes.count > limit ? "\(shown) ... (\(bytes.count) bytes)" : shown
    }
}

enum RobustnessCorpus {
    struct Corpus: Sendable {
        var companionFrames: [[UInt8]]
        var mqttPackets: [[UInt8]]
        var all: [[UInt8]]
    }

    static func build() throws -> Corpus {
        let frames = try companionMessages().map { [UInt8](try $0.encodedFrame()) }
        let packets = try mqttPackets()
        return Corpus(companionFrames: frames, mqttPackets: packets, all: frames + packets)
    }

    static func companionMessages() -> [CompanionMessage] {
        var chunkBytes = [UInt8]()
        chunkBytes.reserveCapacity(3072)
        for i in 0..<3072 { chunkBytes.append(UInt8(truncatingIfNeeded: i &* 31 &+ 7)) }
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        return [
            .hello(
                protocolVersion: 1,
                installationID: "installation-0000-0001",
                capabilities: ["chunk", "resume", "receipt", "commit", "digest.sha256", "reject"]
            ),
            .offer(CompanionOffer(
                batchID: "0192f3c1-0000-0000-0000-0000000000c1",
                idempotencyKey: "0192f3c1-0000-0000-0000-0000000000c1",
                byteCount: 4096,
                digest: digest
            )),
            .resume(fromChunk: 7),
            .receipt(batchID: "0192f3c1-0000-0000-0000-0000000000c1", digest: digest),
            .reject(errorClass: "transient", detail: "retryAfter=30", retryable: true),
            .reject(errorClass: "permanent", detail: "digestMismatch", retryable: false),
            .chunk(seq: 3, bytes: Data(chunkBytes)),
            .chunkAck(seq: 9),
            .commit(digest: digest),
        ]
    }

    static func mqttPackets() throws -> [[UInt8]] {
        var packets: [[UInt8]] = []
        packets.append([UInt8](try MQTTCodec.connect(clientID: "ohe-fuzz-client")))
        packets.append([UInt8](try MQTTCodec.connect(
            clientID: "ohe-fuzz-client",
            keepAlive: 30,
            username: "exporter",
            password: "secretless"
        )))
        packets.append([0x20, 0x02, 0x00, 0x00])
        packets.append([0x40, 0x02, 0x00, 0x2A])
        packets.append([UInt8](try MQTTCodec.publish(
            topic: "ohe/health/batch",
            payload: Data("{\"kind\":\"sample.quantity\"}\n".utf8),
            qos: .atMostOnce,
            packetID: 0
        )))
        packets.append([UInt8](try MQTTCodec.publish(
            topic: "ohe/health/batch",
            payload: Data(repeating: 0x7B, count: 600),
            qos: .atLeastOnce,
            packetID: 42
        )))
        packets.append([UInt8](try MQTTCodec.pingreq()))
        packets.append([UInt8](try MQTTCodec.disconnect()))
        return packets
    }
}

enum RobustnessMutator {
    static let sizeCap = 8192

    static let dictionary: [[UInt8]] = [
        [0xEF, 0xBB, 0xBF],
        [0xC0, 0xAF],
        [0xED, 0xA0, 0x80],
        [0xF0, 0x9F, 0x98, 0x80],
        [0xF4, 0x8F, 0xBF, 0xBF],
        [0xF5, 0x80, 0x80, 0x80],
        [0xC2],
        [0x00, 0x00],
        [0xFF, 0xFF],
        [0x00, 0xFF],
        [0x0A],
    ]

    static func mutate(_ input: [UInt8], corpus: [[UInt8]], rng: inout RobustnessRNG) -> [UInt8] {
        var bytes = input
        for _ in 0..<rng.inRange(1...3) {
            switch rng.below(8) {
            case 0: bitFlip(&bytes, rng: &rng)
            case 1: truncate(&bytes, rng: &rng)
            case 2: extend(&bytes, rng: &rng)
            case 3: splice(&bytes, rng: &rng)
            case 4: corruptDeclaredLength(&bytes, rng: &rng)
            case 5: concatenate(&bytes, corpus: corpus, rng: &rng)
            case 6: dictionarySplice(&bytes, rng: &rng)
            default: duplicateRegion(&bytes, rng: &rng)
            }
        }
        if bytes.count > sizeCap { bytes = Array(bytes[0..<sizeCap]) }
        return bytes
    }

    static func bitFlip(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        guard !bytes.isEmpty else { return }
        for _ in 0..<rng.inRange(1...8) {
            let index = rng.below(bytes.count)
            bytes[index] ^= 1 << UInt8(rng.below(8))
        }
    }

    static func truncate(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        guard !bytes.isEmpty else { return }
        bytes = Array(bytes[0..<rng.below(bytes.count + 1)])
    }

    static func extend(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        bytes.append(contentsOf: rng.bytes(count: rng.inRange(1...32)))
    }

    static func dictionarySplice(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        let word = dictionary[rng.below(dictionary.count)]
        guard bytes.count >= word.count else { return }
        let start = rng.below(bytes.count - word.count + 1)
        for offset in 0..<word.count { bytes[start + offset] = word[offset] }
    }

    static func splice(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        guard !bytes.isEmpty else { return }
        let start = rng.below(bytes.count)
        let length = min(rng.inRange(1...16), bytes.count - start)
        for offset in 0..<length { bytes[start + offset] = rng.byte() }
    }

    static func corruptDeclaredLength(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        guard bytes.count >= 5 else { return }
        if rng.bool() {
            let interesting: [UInt32] = [
                0xFFFF_FFFF,
                0x8000_0000,
                0x7FFF_FFFF,
                0x0010_0001,
                0x0010_0000,
                0x0000_0000,
                0x0000_0001,
                UInt32(truncatingIfNeeded: rng.next()),
            ]
            let encoded = RobustnessBytes.u32(interesting[rng.below(interesting.count)])
            for index in 0..<4 { bytes[index] = encoded[index] }
        } else if rng.bool() {
            for index in 1...min(5, bytes.count - 1) { bytes[index] = 0x80 | UInt8(rng.below(128)) }
        } else {
            let count = rng.inRange(1...min(4, bytes.count - 1))
            for index in 1...count {
                bytes[index] = index == count
                    ? UInt8(rng.below(128))
                    : (0x80 | UInt8(rng.below(128)))
            }
        }
    }

    static func concatenate(_ bytes: inout [UInt8], corpus: [[UInt8]], rng: inout RobustnessRNG) {
        guard !corpus.isEmpty else { return }
        bytes.append(contentsOf: corpus[rng.below(corpus.count)])
    }

    static func duplicateRegion(_ bytes: inout [UInt8], rng: inout RobustnessRNG) {
        guard bytes.count >= 2 else { return }
        let start = rng.below(bytes.count - 1)
        let length = min(rng.inRange(1...32), bytes.count - start)
        bytes.append(contentsOf: bytes[start..<(start + length)])
    }
}

enum RobustnessPristine: Sendable {
    case companionFrame
    case mqttPacket
}

struct RobustnessInput: Sendable {
    var bytes: [UInt8]
    var pristine: RobustnessPristine?
}

struct RobustnessGenerator: Sendable {
    private var rng: RobustnessRNG
    private let corpus: RobustnessCorpus.Corpus

    init(seed: UInt64, corpus: RobustnessCorpus.Corpus) {
        rng = RobustnessRNG(seed: seed)
        self.corpus = corpus
    }

    mutating func next() -> RobustnessInput {
        switch rng.below(10) {
        case 0, 1, 2:
            return RobustnessInput(bytes: rng.bytes(count: rng.inRange(0...4096)), pristine: nil)
        case 3:
            if rng.bool() {
                let frame = corpus.companionFrames[rng.below(corpus.companionFrames.count)]
                return RobustnessInput(bytes: frame, pristine: .companionFrame)
            }
            let packet = corpus.mqttPackets[rng.below(corpus.mqttPackets.count)]
            return RobustnessInput(bytes: packet, pristine: .mqttPacket)
        default:
            let seed = corpus.all[rng.below(corpus.all.count)]
            return RobustnessInput(
                bytes: RobustnessMutator.mutate(seed, corpus: corpus.all, rng: &rng),
                pristine: nil
            )
        }
    }
}

/// Re-emits a payload in canonical form so that a re-encode mismatch can be
/// attributed to a known non-canonical acceptance rather than silently tolerated.
enum RobustnessOracle {
    struct Canonical: Sendable {
        var bytes: [UInt8]
        var widenedBool = false
        var normalizedString = false
    }

    static func canonicalize(_ frame: CompanionFrame) -> Canonical? {
        let bytes = [UInt8](frame.payload)
        var index = 0
        var payload: [UInt8] = []
        var result = Canonical(bytes: [])

        func takeByte() -> UInt8? {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return bytes[index]
        }

        func takeString() -> Bool {
            guard index + 2 <= bytes.count else { return false }
            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2
            guard index + length <= bytes.count else { return false }
            let slice = Array(bytes[index..<(index + length)])
            index += length
            guard let decoded = String(bytes: slice, encoding: .utf8) else { return false }
            let canonical = Array(decoded.utf8)
            if canonical != slice { result.normalizedString = true }
            guard canonical.count <= 65_535 else { return false }
            payload.append(UInt8(canonical.count >> 8))
            payload.append(UInt8(canonical.count & 0xFF))
            payload.append(contentsOf: canonical)
            return true
        }

        switch frame.type {
        case .hello:
            guard let version = takeByte() else { return nil }
            payload.append(version)
            guard takeString() else { return nil }
            guard let capCount = takeByte() else { return nil }
            payload.append(capCount)
            for _ in 0..<Int(capCount) {
                guard takeString() else { return nil }
            }
            guard index == bytes.count else { return nil }
        case .offer:
            for _ in 0..<4 { guard takeString() else { return nil } }
            guard index + 8 <= bytes.count else { return nil }
            payload.append(contentsOf: bytes[index..<(index + 8)])
            index += 8
            guard takeString() else { return nil }
            guard index == bytes.count else { return nil }
        case .resume, .chunkAck:
            guard bytes.count == 4 else { return nil }
            payload.append(contentsOf: bytes)
            index = bytes.count
        case .receipt:
            for _ in 0..<2 { guard takeString() else { return nil } }
            guard index == bytes.count else { return nil }
        case .reject:
            guard let raw = takeByte() else { return nil }
            if raw > 1 { result.widenedBool = true }
            payload.append(raw != 0 ? 1 : 0)
            for _ in 0..<2 { guard takeString() else { return nil } }
            guard index == bytes.count else { return nil }
        case .chunk:
            guard bytes.count >= 4 else { return nil }
            payload.append(contentsOf: bytes)
            index = bytes.count
        case .commit:
            guard takeString() else { return nil }
            guard index == bytes.count else { return nil }
        }

        guard payload.count <= CompanionFrame.maxPayload else { return nil }
        var full = RobustnessBytes.u32(UInt32(payload.count))
        full.append(frame.type.rawValue)
        full.append(contentsOf: payload)
        result.bytes = full
        return result
    }
}

struct RobustnessTally: Sendable {
    var frameDecoded = 0
    var frameIncomplete = 0
    var frameRejected = 0
    var messageDecoded = 0
    var messageRejected = 0
    var mqttDecoded = 0
    var mqttRejected = 0
    var remainingLengthDecoded = 0
    var remainingLengthRejected = 0
    var nativeWireCounted = 0
    var exactReencodes = 0
    var nonCanonicalFrames = 0
    var nonCanonicalBool = 0
    var nonCanonicalString = 0
}

struct RobustnessDefect: Error, CustomStringConvertible {
    var invariant: String
    var target: String
    var iteration: Int
    var detail: String
    var input: [UInt8]

    var description: String {
        """
        \(target) violated: \(invariant)
          iteration: \(iteration)
          detail   : \(detail)
          input    : \(RobustnessBytes.hex(input))
        """
    }
}

/// Enforces the three-state invariant: every input ends as a value, as `nil`
/// (incomplete), or as a thrown error of the codec's own error type.
enum RobustnessDriver {
    static func drive(_ input: RobustnessInput, iteration: Int, into tally: inout RobustnessTally) throws {
        let data = Data(input.bytes)
        try driveCompanion(input, data: data, iteration: iteration, into: &tally)
        try driveMQTT(input, data: data, iteration: iteration, into: &tally)
        try driveRemainingLength(input, data: data, iteration: iteration, into: &tally)

        let text = String(decoding: input.bytes, as: UTF8.self)
        let records = NativeWire.countRecords(in: text)
        guard records >= 0, records <= text.split(whereSeparator: \.isNewline).count else {
            throw RobustnessDefect(
                invariant: "record count must not exceed the line count",
                target: "NativeWire.countRecords",
                iteration: iteration,
                detail: "records=\(records)",
                input: input.bytes
            )
        }
        tally.nativeWireCounted += 1
    }

    private static func driveCompanion(
        _ input: RobustnessInput,
        data: Data,
        iteration: Int,
        into tally: inout RobustnessTally
    ) throws {
        do {
            guard let (frame, consumed) = try CompanionFrame.decodePrefix(data) else {
                tally.frameIncomplete += 1
                guard input.pristine != .companionFrame else {
                    throw RobustnessDefect(
                        invariant: "a canonical frame must decode, not report incomplete",
                        target: "CompanionFrame.decodePrefix",
                        iteration: iteration,
                        detail: "returned nil",
                        input: input.bytes
                    )
                }
                return
            }
            tally.frameDecoded += 1
            guard consumed == 5 + frame.payload.count, consumed <= input.bytes.count else {
                throw RobustnessDefect(
                    invariant: "consumed must equal 5 + payload count and stay inside the buffer",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "consumed=\(consumed) payload=\(frame.payload.count) buffer=\(input.bytes.count)",
                    input: input.bytes
                )
            }
            try driveMessage(
                frame: frame,
                framePrefix: Array(input.bytes[0..<consumed]),
                pristine: input.pristine == .companionFrame,
                iteration: iteration,
                input: input.bytes,
                into: &tally
            )
        } catch let defect as RobustnessDefect {
            throw defect
        } catch is CompanionFrameError {
            tally.frameRejected += 1
            guard input.pristine != .companionFrame else {
                throw RobustnessDefect(
                    invariant: "a canonical frame must not be rejected",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "threw on a self-encoded frame",
                    input: input.bytes
                )
            }
        } catch {
            throw RobustnessDefect(
                invariant: "decodePrefix may only throw CompanionFrameError",
                target: "CompanionFrame.decodePrefix",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input.bytes
            )
        }
    }

    private static func driveMessage(
        frame: CompanionFrame,
        framePrefix: [UInt8],
        pristine: Bool,
        iteration: Int,
        input: [UInt8],
        into tally: inout RobustnessTally
    ) throws {
        do {
            let message = try CompanionMessage.decode(frame)
            tally.messageDecoded += 1
            let reencoded = [UInt8](try message.encodedFrame())
            guard reencoded == framePrefix else {
                let canonical = RobustnessOracle.canonicalize(frame)
                throw RobustnessDefect(
                    invariant: "re-encoding a decoded message must reproduce the original frame bytes",
                    target: "CompanionMessage.decode + encodedFrame",
                    iteration: iteration,
                    detail: "type \(frame.type)\n  original  : \(RobustnessBytes.hex(framePrefix))"
                        + "\n  re-encoded: \(RobustnessBytes.hex(reencoded))"
                        + "\n  widenedBool: \(canonical?.widenedBool ?? false)"
                        + " normalizedString: \(canonical?.normalizedString ?? false)",
                    input: input
                )
            }
            tally.exactReencodes += 1
        } catch let defect as RobustnessDefect {
            throw defect
        } catch is CompanionCodecError {
            tally.messageRejected += 1
            guard !pristine else {
                throw RobustnessDefect(
                    invariant: "a canonical message must not be rejected",
                    target: "CompanionMessage.decode",
                    iteration: iteration,
                    detail: "threw on a self-encoded message",
                    input: input
                )
            }
        } catch {
            throw RobustnessDefect(
                invariant: "CompanionMessage.decode may only throw CompanionCodecError",
                target: "CompanionMessage.decode",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input
            )
        }
    }

    private static func driveMQTT(
        _ input: RobustnessInput,
        data: Data,
        iteration: Int,
        into tally: inout RobustnessTally
    ) throws {
        do {
            let packet = try MQTTCodec.decode(data)
            tally.mqttDecoded += 1
            guard packet.consumed >= 2,
                  packet.consumed <= input.bytes.count,
                  packet.body.count < packet.consumed
            else {
                throw RobustnessDefect(
                    invariant: "consumed must stay inside the buffer and exceed the body",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "consumed=\(packet.consumed) body=\(packet.body.count)",
                    input: input.bytes
                )
            }
            guard input.pristine != .mqttPacket || packet.consumed == input.bytes.count else {
                throw RobustnessDefect(
                    invariant: "a canonical packet must be consumed entirely",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "consumed=\(packet.consumed) buffer=\(input.bytes.count)",
                    input: input.bytes
                )
            }
        } catch let defect as RobustnessDefect {
            throw defect
        } catch is MQTTError {
            tally.mqttRejected += 1
            guard input.pristine != .mqttPacket else {
                throw RobustnessDefect(
                    invariant: "a canonical packet must not be rejected",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "threw on a self-encoded packet",
                    input: input.bytes
                )
            }
        } catch {
            throw RobustnessDefect(
                invariant: "MQTTCodec.decode may only throw MQTTError",
                target: "MQTTCodec.decode",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input.bytes
            )
        }
    }

    private static func driveRemainingLength(
        _ input: RobustnessInput,
        data: Data,
        iteration: Int,
        into tally: inout RobustnessTally
    ) throws {
        for start in [0, 1] {
            do {
                let result = try MQTTRemainingLength.decode(data, start: start)
                tally.remainingLengthDecoded += 1
                guard result.value >= 0,
                      result.value <= 268_435_455,
                      (1...4).contains(result.consumed),
                      start + result.consumed <= input.bytes.count
                else {
                    throw RobustnessDefect(
                        invariant: "a decoded remaining length must be a legal 1-4 byte varint",
                        target: "MQTTRemainingLength.decode",
                        iteration: iteration,
                        detail: "start=\(start) value=\(result.value) consumed=\(result.consumed)",
                        input: input.bytes
                    )
                }
            } catch let defect as RobustnessDefect {
                throw defect
            } catch is MQTTError {
                tally.remainingLengthRejected += 1
            } catch {
                throw RobustnessDefect(
                    invariant: "MQTTRemainingLength.decode may only throw MQTTError",
                    target: "MQTTRemainingLength.decode",
                    iteration: iteration,
                    detail: "start=\(start) threw \(type(of: error)): \(error)",
                    input: input.bytes
                )
            }
        }
    }
}

// MARK: - Bounded in-test fuzz run

@Test func decoderFuzzRunAlwaysEndsInAValueIncompleteOrKnownError() throws {
    let iterations = 2000
    let corpus = try RobustnessCorpus.build()
    var generator = RobustnessGenerator(seed: 0x0BAD_C0DE_0BAD_C0DE, corpus: corpus)
    var tally = RobustnessTally()

    for iteration in 0..<iterations {
        do {
            try RobustnessDriver.drive(generator.next(), iteration: iteration, into: &tally)
        } catch let defect as RobustnessDefect {
            Issue.record("\(defect)")
            return
        }
    }

    // Every input landed in exactly one of the three states, for every target.
    #expect(tally.frameDecoded + tally.frameIncomplete + tally.frameRejected == iterations)
    #expect(tally.messageDecoded + tally.messageRejected == tally.frameDecoded)
    #expect(tally.mqttDecoded + tally.mqttRejected == iterations)
    #expect(tally.remainingLengthDecoded + tally.remainingLengthRejected == iterations * 2)
    #expect(tally.nativeWireCounted == iterations)

    // All three states are actually exercised, so the run is not vacuous.
    #expect(tally.frameDecoded > 0)
    #expect(tally.frameIncomplete > 0)
    #expect(tally.frameRejected > 0)
    #expect(tally.messageDecoded > 0)
    #expect(tally.messageRejected > 0)
    #expect(tally.mqttDecoded > 0)
    #expect(tally.mqttRejected > 0)

    // Round-tripping is byte-exact for every decoded frame: no accepted encoding is
    // non-canonical, so no two wire byte strings decode to the same message.
    #expect(tally.exactReencodes > 0)
    #expect(tally.exactReencodes == tally.messageDecoded)
    #expect(tally.nonCanonicalFrames == 0)
}

@Test func declaredFrameLengthIsValidatedBeforeAnyAllocation() throws {
    // 0xFFFFFFFF would be a 4 GiB buffer. Sizing before validating would either hang
    // or blow up; rejecting first keeps this loop in the millisecond range.
    let huge = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x01])
    let atMaxButShort = Data([0x00, 0x10, 0x00, 0x00, 0x01, 0x02])
    let iterations = 50_000
    var rejected = 0
    var incomplete = 0

    let started = Date()
    for _ in 0..<iterations {
        do {
            _ = try CompanionFrame.decodePrefix(huge)
        } catch CompanionFrameError.tooLarge {
            rejected += 1
        }
        if try CompanionFrame.decodePrefix(atMaxButShort) == nil { incomplete += 1 }
    }
    let elapsed = Date().timeIntervalSince(started)

    #expect(rejected == iterations)
    #expect(incomplete == iterations)
    #expect(elapsed < 5)
}

// MARK: - Adversarial companion frames

@Test func companionFrameRejectsMaximalDeclaredLength() throws {
    #expect(throws: CompanionFrameError.tooLarge) {
        _ = try CompanionFrame.decodePrefix(Data([0xFF, 0xFF, 0xFF, 0xFF, 0x01]))
    }
    #expect(throws: CompanionFrameError.tooLarge) {
        // maxPayload + 1.
        _ = try CompanionFrame.decodePrefix(Data([0x00, 0x10, 0x00, 0x01, 0x01]))
    }
}

@Test func companionFrameRejectsUnknownTypeByte() throws {
    #expect(throws: CompanionFrameError.badType(0x63)) {
        _ = try CompanionFrame.decodePrefix(Data([0x00, 0x00, 0x00, 0x00, 0x63]))
    }
    #expect(throws: CompanionFrameError.badType(0x00)) {
        _ = try CompanionFrame.decodePrefix(Data([0x00, 0x00, 0x00, 0x00, 0x00]))
    }
}

@Test func companionFrameShorterThanTheHeaderIsIncompleteNotAnError() throws {
    // Four bytes cannot even hold the length prefix and type byte, so the decoder
    // must ask for more input rather than guess.
    #expect(try CompanionFrame.decodePrefix(Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
    #expect(try CompanionFrame.decodePrefix(Data()) == nil)
}

@Test func companionFixedWidthPayloadsRejectTheWrongWidth() throws {
    #expect(throws: CompanionCodecError.trailingBytes) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .resume, payload: Data([0x00, 0x00, 0x00, 0x01, 0x99]))
        )
    }
    #expect(throws: CompanionCodecError.trailingBytes) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .resume, payload: Data([0x00, 0x00, 0x00]))
        )
    }
    #expect(throws: CompanionCodecError.trailingBytes) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .chunkAck, payload: Data([0x00, 0x00, 0x00, 0x01, 0x99]))
        )
    }
    #expect(throws: CompanionCodecError.trailingBytes) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .chunkAck, payload: Data([0x00, 0x00, 0x00]))
        )
    }
}

@Test func companionStringClaimingMoreBytesThanRemainIsTruncated() throws {
    // Declares a 16-byte digest but supplies one byte.
    #expect(throws: CompanionCodecError.truncated) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .commit, payload: Data([0x00, 0x10, 0x61]))
        )
    }
    // Not even room for the two-byte length prefix.
    #expect(throws: CompanionCodecError.truncated) {
        _ = try CompanionMessage.decode(CompanionFrame(type: .commit, payload: Data([0x00])))
    }
}

@Test func companionInvalidUTF8InAStringFieldIsRejected() throws {
    // 0xC0 0xAF is an overlong encoding of '/'.
    #expect(throws: CompanionCodecError.badUTF8) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .commit, payload: Data([0x00, 0x02, 0xC0, 0xAF]))
        )
    }
    // 0xED 0xA0 0x80 is a lone surrogate half.
    #expect(throws: CompanionCodecError.badUTF8) {
        _ = try CompanionMessage.decode(
            CompanionFrame(type: .commit, payload: Data([0x00, 0x03, 0xED, 0xA0, 0x80]))
        )
    }
}

@Test func companionHelloDeclaringMoreCapabilitiesThanPresentIsTruncated() throws {
    var payload = Data([0x01])                      // protocol version
    payload.append(contentsOf: [0x00, 0x02, 0x69, 0x64]) // installationID "id"
    payload.append(0x03)                            // claims three capabilities
    payload.append(contentsOf: [0x00, 0x01, 0x61])  // supplies one, "a"
    #expect(throws: CompanionCodecError.truncated) {
        _ = try CompanionMessage.decode(CompanionFrame(type: .hello, payload: payload))
    }
}

@Test func companionDecodePrefixSplitsTwoFramesInOneBuffer() throws {
    let first = CompanionMessage.chunkAck(seq: 11)
    let second = CompanionMessage.commit(digest: "sha256:deadbeef")
    let firstBytes = try first.encodedFrame()
    var buffer = firstBytes
    buffer.append(try second.encodedFrame())

    guard let head = try CompanionFrame.decodePrefix(buffer) else {
        Issue.record("expected the first frame to decode")
        return
    }
    #expect(head.consumed == firstBytes.count)
    #expect(try CompanionMessage.decode(head.frame) == first)

    let remainder = Data(buffer[head.consumed...])
    guard let tail = try CompanionFrame.decodePrefix(remainder) else {
        Issue.record("expected the second frame to decode")
        return
    }
    #expect(tail.consumed == remainder.count)
    #expect(try CompanionMessage.decode(tail.frame) == second)
}

/// The two byte-level asymmetries the fuzzer found, now rejected. Both were decoder-side
/// tolerance of non-canonical input, which let distinct wire bytes decode to one message —
/// unsafe in a protocol that de-duplicates on digests and idempotency keys.
@Test func companionDecoderRejectsNonCanonicalEncodings() throws {
    // A `reject` retryable byte outside {0, 1} was widened to `true`.
    var rejectPayload = Data([0x09])
    rejectPayload.append(contentsOf: [0x00, 0x01, 0x61])
    rejectPayload.append(contentsOf: [0x00, 0x01, 0x62])
    #expect(throws: CompanionCodecError.badBoolean(0x09)) {
        _ = try CompanionMessage.decode(CompanionFrame(type: .reject, payload: rejectPayload))
    }
    for canonical: UInt8 in [0, 1] {
        var payload = Data([canonical])
        payload.append(contentsOf: [0x00, 0x01, 0x61])
        payload.append(contentsOf: [0x00, 0x01, 0x62])
        let frame = CompanionFrame(type: .reject, payload: payload)
        let message = try CompanionMessage.decode(frame)
        #expect(message == .reject(errorClass: "a", detail: "b", retryable: canonical == 1))
        #expect(try message.encodedFrame() == frame.encode())
    }

    // A leading UTF-8 BOM in a string field was stripped by Foundation's UTF-8 decode, so the
    // frame re-encoded three bytes shorter. It is now preserved and round-trips exactly.
    var commitPayload = Data([0x00, 0x05])
    commitPayload.append(contentsOf: [0xEF, 0xBB, 0xBF, 0x61, 0x62])
    let commitFrame = CompanionFrame(type: .commit, payload: commitPayload)
    let commitMessage = try CompanionMessage.decode(commitFrame)
    #expect(commitMessage == .commit(digest: "\u{FEFF}ab"))
    #expect(try commitMessage.encodedFrame() == commitFrame.encode())
}

// MARK: - Adversarial MQTT packets

@Test func mqttRemainingLengthRejectsFiveContinuationBytes() throws {
    #expect(throws: MQTTError.remainingLength) {
        _ = try MQTTRemainingLength.decode(Data([0x80, 0x80, 0x80, 0x80, 0x80, 0x01]), start: 0)
    }
    // Four continuation bytes with nothing following is merely incomplete.
    #expect(throws: MQTTError.truncated) {
        _ = try MQTTRemainingLength.decode(Data([0x80, 0x80, 0x80, 0x80]), start: 0)
    }
}

@Test func mqttRefusesSubscribePacketType() throws {
    // This client only publishes; SUBSCRIBE (type 8) has no representation at all.
    #expect(throws: MQTTError.unexpectedPacket(8)) {
        _ = try MQTTCodec.decode(Data([0x82, 0x00]))
    }
    #expect(throws: MQTTError.unexpectedPacket(0)) {
        _ = try MQTTCodec.decode(Data([0x00, 0x00]))
    }
}
