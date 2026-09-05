import CompanionWire
import Foundation
import MQTTCodec
import WireFormat

// R-84: the companion and MQTT wire decoders are fuzzable on Linux with no second
// device. Deterministic and seeded — no libFuzzer, no sanitizer coverage, no
// SystemRandomNumberGenerator, so a failing seed reproduces byte-for-byte anywhere.

// MARK: - PRNG

/// splitmix64. Fixed width arithmetic only, so the stream is identical on every host.
struct SplitMix64: Sendable {
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

    /// Uniform-enough in `0..<upper`; modulo bias is irrelevant for corpus selection.
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

// MARK: - Byte helpers

enum WireBytes {
    static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func hexDump(_ bytes: [UInt8], limit: Int = 512) -> String {
        let shown = Array(bytes.prefix(limit))
        var lines: [String] = []
        var offset = 0
        while offset < shown.count {
            let end = min(offset + 16, shown.count)
            let hex = shown[offset..<end].map { String(format: "%02x", $0) }.joined(separator: " ")
            lines.append(String(format: "  %06x  %@", offset, hex))
            offset = end
        }
        if bytes.count > shown.count {
            lines.append("  ... \(bytes.count - shown.count) more byte(s) elided")
        }
        return lines.isEmpty ? "  <empty>" : lines.joined(separator: "\n")
    }
}

// MARK: - Corpus of valid inputs

enum FuzzCorpus {
    struct Corpus: Sendable {
        var companionFrames: [[UInt8]]
        var mqttPackets: [[UInt8]]
        var all: [[UInt8]]
    }

    /// One valid frame per `CompanionMessage` case, plus the MQTT packets a
    /// publish-only client can legitimately send or receive.
    static func build() throws -> Corpus {
        let companionFrames = try companionMessages().map { [UInt8](try $0.encodedFrame()) }
        let mqttPackets = try mqttPackets()
        return Corpus(
            companionFrames: companionFrames,
            mqttPackets: mqttPackets,
            all: companionFrames + mqttPackets
        )
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
        // CONNACK / PUBACK have no public builder in MQTTCodec; they are broker->client.
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

// MARK: - Structured mutation

enum FuzzMutator {
    /// Mutated inputs stay under 8 KiB: the largest seed is a ~3 KiB chunk frame and
    /// concatenation can pair two seeds, so this bounds memory without clipping seeds.
    static let sizeCap = 8192

    static func mutate(_ input: [UInt8], corpus: [[UInt8]], rng: inout SplitMix64) -> [UInt8] {
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

    static func bitFlip(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        guard !bytes.isEmpty else { return }
        for _ in 0..<rng.inRange(1...8) {
            let index = rng.below(bytes.count)
            bytes[index] ^= 1 << UInt8(rng.below(8))
        }
    }

    static func truncate(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        guard !bytes.isEmpty else { return }
        bytes = Array(bytes[0..<rng.below(bytes.count + 1)])
    }

    static func extend(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        bytes.append(contentsOf: rng.bytes(count: rng.inRange(1...32)))
    }

    /// Byte sequences that random flipping will essentially never produce, but that
    /// sit on the interesting edges of UTF-8 validation and u16 length prefixes.
    static let dictionary: [[UInt8]] = [
        [0xEF, 0xBB, 0xBF],       // UTF-8 BOM
        [0xC0, 0xAF],             // overlong '/'
        [0xED, 0xA0, 0x80],       // CESU-8 surrogate half
        [0xF0, 0x9F, 0x98, 0x80], // astral scalar
        [0xF4, 0x8F, 0xBF, 0xBF], // U+10FFFF
        [0xF5, 0x80, 0x80, 0x80], // above U+10FFFF
        [0xC2],                   // dangling 2-byte lead
        [0x00, 0x00],
        [0xFF, 0xFF],
        [0x00, 0xFF],
        [0x0A],
    ]

    static func dictionarySplice(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        let word = dictionary[rng.below(dictionary.count)]
        guard bytes.count >= word.count else { return }
        let start = rng.below(bytes.count - word.count + 1)
        for offset in 0..<word.count { bytes[start + offset] = word[offset] }
    }

    static func splice(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        guard !bytes.isEmpty else { return }
        let start = rng.below(bytes.count)
        let length = min(rng.inRange(1...16), bytes.count - start)
        for offset in 0..<length { bytes[start + offset] = rng.byte() }
    }

    /// Attacks the two self-describing length fields directly: the companion frame's
    /// big-endian u32 prefix and MQTT's varint remaining length.
    static func corruptDeclaredLength(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        guard bytes.count >= 5 else { return }
        if rng.bool() {
            let interesting: [UInt32] = [
                0xFFFF_FFFF,
                0x8000_0000,
                0x7FFF_FFFF,
                0x0010_0001, // maxPayload + 1
                0x0010_0000, // maxPayload
                0x0000_0000,
                0x0000_0001,
                UInt32(truncatingIfNeeded: rng.next()),
            ]
            let encoded = WireBytes.u32(interesting[rng.below(interesting.count)])
            for index in 0..<4 { bytes[index] = encoded[index] }
        } else if rng.bool() {
            // Five continuation bytes: illegal remaining length.
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

    static func concatenate(_ bytes: inout [UInt8], corpus: [[UInt8]], rng: inout SplitMix64) {
        guard !corpus.isEmpty else { return }
        bytes.append(contentsOf: corpus[rng.below(corpus.count)])
    }

    static func duplicateRegion(_ bytes: inout [UInt8], rng: inout SplitMix64) {
        guard bytes.count >= 2 else { return }
        let start = rng.below(bytes.count - 1)
        let length = min(rng.inRange(1...32), bytes.count - start)
        bytes.append(contentsOf: bytes[start..<(start + length)])
    }
}

// MARK: - Input generation

enum PristineKind: Sendable {
    case companionFrame
    case mqttPacket
}

struct GeneratedInput: Sendable {
    var bytes: [UInt8]
    var pristine: PristineKind?
}

struct FuzzGenerator: Sendable {
    private var rng: SplitMix64
    private let corpus: FuzzCorpus.Corpus

    init(seed: UInt64, corpus: FuzzCorpus.Corpus) {
        rng = SplitMix64(seed: seed)
        self.corpus = corpus
    }

    mutating func next() -> GeneratedInput {
        switch rng.below(10) {
        case 0, 1, 2:
            // Uniformly random bytes, 0...4096.
            return GeneratedInput(bytes: rng.bytes(count: rng.inRange(0...4096)), pristine: nil)
        case 3:
            if rng.bool() {
                let frame = corpus.companionFrames[rng.below(corpus.companionFrames.count)]
                return GeneratedInput(bytes: frame, pristine: .companionFrame)
            }
            let packet = corpus.mqttPackets[rng.below(corpus.mqttPackets.count)]
            return GeneratedInput(bytes: packet, pristine: .mqttPacket)
        default:
            let seed = corpus.all[rng.below(corpus.all.count)]
            return GeneratedInput(
                bytes: FuzzMutator.mutate(seed, corpus: corpus.all, rng: &rng),
                pristine: nil
            )
        }
    }
}

// MARK: - Re-encode oracle

/// Mirrors `CompanionMessage.decode`'s payload layout and re-emits it in canonical
/// form. Used to attribute a re-encode mismatch to a *known* non-canonical
/// acceptance instead of silently tolerating it. Anything the oracle cannot explain
/// is a defect.
enum FrameOracle {
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
            // Same lossy transform the decoder performs.
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
        var full = WireBytes.u32(UInt32(payload.count))
        full.append(frame.type.rawValue)
        full.append(contentsOf: payload)
        result.bytes = full
        return result
    }
}

// MARK: - Outcome tallies

struct Tally: Sendable {
    var decoded = 0
    var incomplete = 0
    var rejected = 0

    var description: String { "\(decoded)/\(incomplete)/\(rejected)" }
}

struct NonCanonicalFinding: Sendable {
    var cause: String
    var iteration: Int
    var hex: String
}

struct Outcomes: Sendable {
    var frame = Tally()
    var message = Tally()
    var mqtt = Tally()
    var remainingLength = Tally()
    var nativeWire = Tally()
    var exactReencodes = 0
    var nonCanonicalFrames = 0
    var nonCanonicalBool = 0
    var nonCanonicalString = 0
    var findings: [NonCanonicalFinding] = []

    mutating func record(_ cause: String, iteration: Int, bytes: [UInt8]) {
        guard findings.count < 6 else { return }
        guard !findings.contains(where: { $0.cause == cause }) else { return }
        findings.append(NonCanonicalFinding(
            cause: cause,
            iteration: iteration,
            hex: WireBytes.hexDump(bytes, limit: 64)
        ))
    }
}

struct FuzzDefect: Error, Sendable {
    var invariant: String
    var target: String
    var iteration: Int
    var detail: String
    var input: [UInt8]

    func report(seed: UInt64) -> String {
        """
        wirefuzz: DEFECT
          invariant : \(invariant)
          target    : \(target)
          seed      : 0x\(String(seed, radix: 16, uppercase: false))
          iteration : \(iteration)
          detail    : \(detail)
          input     : \(input.count) byte(s)
        \(WireBytes.hexDump(input))
        """
    }
}

// MARK: - Targets

enum FuzzTargets {
    /// Drives every decoder over one input and enforces the three-state invariant:
    /// a value, `nil` (incomplete), or a thrown error of a known type. Anything else
    /// — including a trap, which kills the process — is a defect.
    static func drive(_ input: GeneratedInput, iteration: Int, into tally: inout Outcomes) throws {
        let data = Data(input.bytes)
        try driveCompanion(input, data: data, iteration: iteration, into: &tally)
        try driveMQTT(input, data: data, iteration: iteration, into: &tally)
        try driveRemainingLength(input, data: data, iteration: iteration, into: &tally)
        try driveNativeWire(input, iteration: iteration, into: &tally)
    }

    private static func driveCompanion(
        _ input: GeneratedInput,
        data: Data,
        iteration: Int,
        into tally: inout Outcomes
    ) throws {
        do {
            guard let (frame, consumed) = try CompanionFrame.decodePrefix(data) else {
                tally.frame.incomplete += 1
                if input.pristine == .companionFrame {
                    throw FuzzDefect(
                        invariant: "a canonical frame must decode, not report incomplete",
                        target: "CompanionFrame.decodePrefix",
                        iteration: iteration,
                        detail: "decodePrefix returned nil for a self-encoded frame",
                        input: input.bytes
                    )
                }
                return
            }
            tally.frame.decoded += 1
            guard consumed == 5 + frame.payload.count, consumed <= input.bytes.count else {
                throw FuzzDefect(
                    invariant: "consumed must equal 5 + payload count and stay inside the buffer",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "consumed=\(consumed) payload=\(frame.payload.count) buffer=\(input.bytes.count)",
                    input: input.bytes
                )
            }
            if input.pristine == .companionFrame, consumed != input.bytes.count {
                throw FuzzDefect(
                    invariant: "a canonical frame must be consumed entirely",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "consumed=\(consumed) buffer=\(input.bytes.count)",
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
        } catch let defect as FuzzDefect {
            throw defect
        } catch is CompanionFrameError {
            tally.frame.rejected += 1
            if input.pristine == .companionFrame {
                throw FuzzDefect(
                    invariant: "a canonical frame must not be rejected",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "decodePrefix threw on a self-encoded frame",
                    input: input.bytes
                )
            }
        } catch {
            throw FuzzDefect(
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
        into tally: inout Outcomes
    ) throws {
        do {
            let message = try CompanionMessage.decode(frame)
            tally.message.decoded += 1
            try checkReencode(
                message: message,
                frame: frame,
                framePrefix: framePrefix,
                pristine: pristine,
                iteration: iteration,
                input: input,
                into: &tally
            )
        } catch let defect as FuzzDefect {
            throw defect
        } catch is CompanionCodecError {
            tally.message.rejected += 1
            if pristine {
                throw FuzzDefect(
                    invariant: "a canonical message must not be rejected",
                    target: "CompanionMessage.decode",
                    iteration: iteration,
                    detail: "decode threw on a self-encoded message",
                    input: input
                )
            }
        } catch {
            throw FuzzDefect(
                invariant: "CompanionMessage.decode may only throw CompanionCodecError",
                target: "CompanionMessage.decode",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input
            )
        }
    }

    private static func checkReencode(
        message: CompanionMessage,
        frame: CompanionFrame,
        framePrefix: [UInt8],
        pristine: Bool,
        iteration: Int,
        input: [UInt8],
        into tally: inout Outcomes
    ) throws {
        let reencoded: [UInt8]
        do {
            reencoded = [UInt8](try message.encodedFrame())
        } catch {
            throw FuzzDefect(
                invariant: "a decoded message must always re-encode",
                target: "CompanionMessage.encodedFrame",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input
            )
        }

        if reencoded == framePrefix {
            tally.exactReencodes += 1
            return
        }

        // Any surviving mismatch is a defect. The oracle no longer excuses one: the decoder
        // rejects the non-canonical encodings it used to accept, so two distinct wire byte
        // strings can no longer decode to the same message. The attribution is kept only to
        // make a regression legible in the report.
        let canonical = FrameOracle.canonicalize(frame)
        if canonical?.widenedBool == true {
            tally.nonCanonicalBool += 1
            tally.record(
                "reject.retryable byte outside {0,1} was accepted and re-encoded as 1",
                iteration: iteration,
                bytes: framePrefix
            )
        }
        if canonical?.normalizedString == true {
            tally.nonCanonicalString += 1
            tally.record(
                "length-prefixed string was rewritten by the UTF-8 decode (BOM stripped)",
                iteration: iteration,
                bytes: framePrefix
            )
        }
        tally.nonCanonicalFrames += 1
        throw FuzzDefect(
            invariant: "re-encoding a decoded message must reproduce the original frame bytes",
            target: "CompanionMessage.decode + encodedFrame",
            iteration: iteration,
            detail: "frame type \(frame.type), original \(framePrefix.count) byte(s), "
                + "re-encoded \(reencoded.count) byte(s), pristine input: \(pristine)\n"
                + "  original  :\n\(WireBytes.hexDump(framePrefix))\n"
                + "  re-encoded:\n\(WireBytes.hexDump(reencoded))",
            input: input
        )
    }

    private static func driveMQTT(
        _ input: GeneratedInput,
        data: Data,
        iteration: Int,
        into tally: inout Outcomes
    ) throws {
        do {
            let packet = try MQTTCodec.decode(data)
            tally.mqtt.decoded += 1
            guard packet.consumed >= 2,
                  packet.consumed <= input.bytes.count,
                  packet.body.count < packet.consumed
            else {
                throw FuzzDefect(
                    invariant: "consumed must stay inside the buffer and exceed the body",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "consumed=\(packet.consumed) body=\(packet.body.count) buffer=\(input.bytes.count)",
                    input: input.bytes
                )
            }
            if input.pristine == .mqttPacket, packet.consumed != input.bytes.count {
                throw FuzzDefect(
                    invariant: "a canonical packet must be consumed entirely",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "consumed=\(packet.consumed) buffer=\(input.bytes.count)",
                    input: input.bytes
                )
            }
        } catch let defect as FuzzDefect {
            throw defect
        } catch is MQTTError {
            tally.mqtt.rejected += 1
            if input.pristine == .mqttPacket {
                throw FuzzDefect(
                    invariant: "a canonical packet must not be rejected",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "decode threw on a self-encoded packet",
                    input: input.bytes
                )
            }
        } catch {
            throw FuzzDefect(
                invariant: "MQTTCodec.decode may only throw MQTTError",
                target: "MQTTCodec.decode",
                iteration: iteration,
                detail: "threw \(type(of: error)): \(error)",
                input: input.bytes
            )
        }
    }

    private static func driveRemainingLength(
        _ input: GeneratedInput,
        data: Data,
        iteration: Int,
        into tally: inout Outcomes
    ) throws {
        for start in [0, 1] {
            do {
                let result = try MQTTRemainingLength.decode(data, start: start)
                tally.remainingLength.decoded += 1
                guard result.value >= 0,
                      result.value <= 268_435_455,
                      (1...4).contains(result.consumed),
                      start + result.consumed <= input.bytes.count
                else {
                    throw FuzzDefect(
                        invariant: "a decoded remaining length must be a legal 1-4 byte varint",
                        target: "MQTTRemainingLength.decode",
                        iteration: iteration,
                        detail: "start=\(start) value=\(result.value) consumed=\(result.consumed)",
                        input: input.bytes
                    )
                }
            } catch let defect as FuzzDefect {
                throw defect
            } catch is MQTTError {
                tally.remainingLength.rejected += 1
            } catch {
                throw FuzzDefect(
                    invariant: "MQTTRemainingLength.decode may only throw MQTTError",
                    target: "MQTTRemainingLength.decode",
                    iteration: iteration,
                    detail: "start=\(start) threw \(type(of: error)): \(error)",
                    input: input.bytes
                )
            }
        }
    }

    private static func driveNativeWire(
        _ input: GeneratedInput,
        iteration: Int,
        into tally: inout Outcomes
    ) throws {
        // Lossy UTF-8: arbitrary bytes become text with replacement characters.
        let text = String(decoding: input.bytes, as: UTF8.self)
        let records = NativeWire.countRecords(in: text)
        let lines = text.split(whereSeparator: \.isNewline).count
        guard records >= 0, records <= lines else {
            throw FuzzDefect(
                invariant: "record count must be non-negative and no greater than the line count",
                target: "NativeWire.countRecords",
                iteration: iteration,
                detail: "records=\(records) lines=\(lines)",
                input: input.bytes
            )
        }
        tally.nativeWire.decoded += 1
    }
}

// MARK: - Declared-length allocation guard

/// A declared length must be validated against the buffer before anything is
/// allocated for it. `0xFFFFFFFF` would be a 4 GiB allocation; a decoder that sized
/// a buffer first would either hang or blow up here. Timing plus (on Linux) the
/// resident-set delta stands in for an allocation counter that Foundation does not
/// expose.
enum AllocationGuard {
    struct Result: Sendable {
        var iterations: Int
        var seconds: Double
        var residentDeltaKiB: Int?
    }

    static func run(iterations: Int) throws -> Result {
        let hugeFrame = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        let overMaxFrame = Data([0x00, 0x10, 0x00, 0x01, 0x01])
        let atMaxFrame = Data([0x00, 0x10, 0x00, 0x00, 0x01, 0x02, 0x03])
        let shortFrame = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let hugeMQTT = Data([0x30, 0xFF, 0xFF, 0xFF, 0x7F])

        let before = residentKiB()
        let started = Date()
        for iteration in 0..<iterations {
            try expect(.tooLarge, from: hugeFrame, iteration: iteration, label: "declared length 0xFFFFFFFF")
            try expect(.tooLarge, from: overMaxFrame, iteration: iteration, label: "declared length maxPayload+1")
            try expectIncomplete(atMaxFrame, iteration: iteration, label: "declared length maxPayload, short buffer")
            try expectIncomplete(shortFrame, iteration: iteration, label: "4-byte buffer")
            do {
                _ = try MQTTCodec.decode(hugeMQTT)
                throw FuzzDefect(
                    invariant: "a remaining length beyond the buffer must be refused",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "268435455-byte remaining length in a 5-byte buffer decoded",
                    input: [UInt8](hugeMQTT)
                )
            } catch let defect as FuzzDefect {
                throw defect
            } catch MQTTError.truncated {
                continue
            } catch {
                throw FuzzDefect(
                    invariant: "a remaining length beyond the buffer must throw MQTTError.truncated",
                    target: "MQTTCodec.decode",
                    iteration: iteration,
                    detail: "threw \(type(of: error)): \(error)",
                    input: [UInt8](hugeMQTT)
                )
            }
        }
        let seconds = Date().timeIntervalSince(started)
        let after = residentKiB()

        // 4 GiB per call would be minutes, not milliseconds.
        guard seconds < 10 else {
            throw FuzzDefect(
                invariant: "declared lengths must be validated before allocation",
                target: "CompanionFrame.decodePrefix",
                iteration: iterations,
                detail: String(format: "%d pathological decodes took %.2fs", iterations * 5, seconds),
                input: [UInt8](hugeFrame)
            )
        }

        var delta: Int?
        if let before, let after { delta = after - before }
        if let delta, delta > 65_536 {
            throw FuzzDefect(
                invariant: "declared lengths must be validated before allocation",
                target: "CompanionFrame.decodePrefix",
                iteration: iterations,
                detail: "resident set grew \(delta) KiB across \(iterations * 5) pathological decodes",
                input: [UInt8](hugeFrame)
            )
        }

        return Result(iterations: iterations, seconds: seconds, residentDeltaKiB: delta)
    }

    private static func expect(
        _ expected: CompanionFrameError,
        from data: Data,
        iteration: Int,
        label: String
    ) throws {
        do {
            _ = try CompanionFrame.decodePrefix(data)
        } catch let error as CompanionFrameError where error == expected {
            return
        } catch {
            throw FuzzDefect(
                invariant: "\(label) must throw \(expected)",
                target: "CompanionFrame.decodePrefix",
                iteration: iteration,
                detail: "threw \(error)",
                input: [UInt8](data)
            )
        }
        throw FuzzDefect(
            invariant: "\(label) must throw \(expected)",
            target: "CompanionFrame.decodePrefix",
            iteration: iteration,
            detail: "did not throw",
            input: [UInt8](data)
        )
    }

    private static func expectIncomplete(_ data: Data, iteration: Int, label: String) throws {
        do {
            guard try CompanionFrame.decodePrefix(data) == nil else {
                throw FuzzDefect(
                    invariant: "\(label) must report incomplete",
                    target: "CompanionFrame.decodePrefix",
                    iteration: iteration,
                    detail: "returned a frame",
                    input: [UInt8](data)
                )
            }
        } catch let defect as FuzzDefect {
            throw defect
        } catch {
            throw FuzzDefect(
                invariant: "\(label) must report incomplete, not throw",
                target: "CompanionFrame.decodePrefix",
                iteration: iteration,
                detail: "threw \(error)",
                input: [UInt8](data)
            )
        }
    }

    /// Linux only; nil elsewhere, where the timing bound is the only signal.
    static func residentKiB() -> Int? {
        guard let raw = FileManager.default.contents(atPath: "/proc/self/statm") else { return nil }
        let fields = String(decoding: raw, as: UTF8.self).split(separator: " ")
        guard fields.count >= 2, let pages = Int(fields[1]) else { return nil }
        return pages * 4
    }
}

// MARK: - CLI

struct Options: Sendable {
    static let defaultSeed: UInt64 = 0xA5A5_5A5A_DEAD_BEEF
    static let defaultIterations = 20_000

    var seed = defaultSeed
    var iterations = defaultIterations

    static let usage = """
    usage: wirefuzz [--seed <UInt64>] [--iterations <Int>]

      --seed <UInt64>      PRNG seed; decimal or 0x-prefixed hex (default \
    0x\(String(defaultSeed, radix: 16))).
      --iterations <Int>   Number of fuzz iterations, 1 or more (default \(defaultIterations)).
      -h, --help           Print this message.

    Exit codes: 0 clean, 1 defect found, 2 bad usage.
    """

    enum Parsed: Sendable {
        case ok(Options)
        case help
        case invalid(String)
    }

    static func parse(_ arguments: [String]) -> Parsed {
        var options = Options()
        var index = 0
        // `swift run wirefuzz -- --iterations N` forwards the bare separator.
        while index < arguments.count, arguments[index] == "--" { index += 1 }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                return .help
            case "--seed":
                guard index + 1 < arguments.count else { return .invalid("--seed requires a value") }
                guard let value = parseUInt64(arguments[index + 1]) else {
                    return .invalid("--seed: '\(arguments[index + 1])' is not a UInt64")
                }
                options.seed = value
                index += 2
            case "--iterations":
                guard index + 1 < arguments.count else { return .invalid("--iterations requires a value") }
                guard let value = Int(arguments[index + 1]), value > 0 else {
                    return .invalid("--iterations: '\(arguments[index + 1])' is not a positive Int")
                }
                options.iterations = value
                index += 2
            default:
                return .invalid("unknown argument '\(argument)'")
            }
        }
        return .ok(options)
    }

    private static func parseUInt64(_ text: String) -> UInt64? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt64(text.dropFirst(2), radix: 16)
        }
        return UInt64(text)
    }
}

// MARK: - Entry point

@main
struct WireFuzz {
    static func main() {
        let options: Options
        switch Options.parse(Array(CommandLine.arguments.dropFirst())) {
        case .help:
            print(Options.usage)
            exit(0)
        case .invalid(let message):
            printError("wirefuzz: \(message)")
            printError(Options.usage)
            exit(2)
        case .ok(let parsed):
            options = parsed
        }

        do {
            let (tally, guardResult) = try fuzz(options)
            report(options: options, tally: tally, guardResult: guardResult)
            exit(0)
        } catch let defect as FuzzDefect {
            printError(defect.report(seed: options.seed))
            printError("wirefuzz: reproduce with --seed 0x\(String(options.seed, radix: 16)) "
                + "--iterations \(options.iterations)")
            exit(1)
        } catch {
            printError("wirefuzz: unexpected failure: \(error)")
            exit(1)
        }
    }

    private static func fuzz(_ options: Options) throws -> (Outcomes, AllocationGuard.Result) {
        let corpus = try FuzzCorpus.build()
        var generator = FuzzGenerator(seed: options.seed, corpus: corpus)
        var tally = Outcomes()
        for iteration in 0..<options.iterations {
            try FuzzTargets.drive(generator.next(), iteration: iteration, into: &tally)
        }
        return (tally, try AllocationGuard.run(iterations: 200_000))
    }

    private static func report(
        options: Options,
        tally: Outcomes,
        guardResult: AllocationGuard.Result
    ) {
        let rss = guardResult.residentDeltaKiB.map { "\($0)KiB" } ?? "n/a"
        let guardNote = String(
            format: "lengthGuard=%d in %.3fs rssDelta=%@",
            guardResult.iterations * 5,
            guardResult.seconds,
            rss
        )
        print(
            "wirefuzz ok seed=0x\(String(options.seed, radix: 16)) iterations=\(options.iterations) "
                + "decoded/incomplete/rejected frame=\(tally.frame.description) "
                + "message=\(tally.message.description) mqtt=\(tally.mqtt.description) "
                + "remainingLength=\(tally.remainingLength.description) "
                + "nativeWire=\(tally.nativeWire.description) "
                + "exactReencodes=\(tally.exactReencodes) "
                + "nonCanonical=\(tally.nonCanonicalFrames)"
                + "(bool:\(tally.nonCanonicalBool),utf8:\(tally.nonCanonicalString)) "
                + guardNote
        )
        guard !tally.findings.isEmpty else { return }
        print("wirefuzz: non-canonical encodings accepted (re-encode is not byte-identical):")
        for finding in tally.findings {
            print("  - \(finding.cause) (first seen at iteration \(finding.iteration))")
            print(finding.hex)
        }
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
