import Foundation

/// RFC 4122 UUID version 5 (SHA-1 name-based). Used for deterministic series chunk IDs.
public enum UUIDV5 {
    public static let urlNamespace = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!

    /// Namespace for `ohe.wire/1` series chunk UUIDs: v5(URL namespace, "ohe.wire/1/series").
    public static let seriesNamespace = uuid(
        namespace: urlNamespace,
        name: Data("ohe.wire/1/series".utf8)
    )

    public static func uuid(namespace: UUID, name: Data) -> UUID {
        var material = uuidBytes(namespace)
        material.append(name)
        var digest = Array(SHA1.hash(material))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            )
        )
    }

    public static func seriesChunk(
        parentUUID: String,
        kind: String,
        chunkIndex: Int
    ) -> String {
        uuid(
            namespace: seriesNamespace,
            name: Data("\(parentUUID.lowercased())|\(kind)|\(chunkIndex)".utf8)
        ).uuidString.lowercased()
    }

    private static func uuidBytes(_ uuid: UUID) -> Data {
        let bytes = uuid.uuid
        return Data([
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15,
        ])
    }
}

enum SHA1 {
    static func hash(_ data: Data) -> Data {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalize()
    }

    struct Hasher {
        private var h0: UInt32 = 0x6745_2301
        private var h1: UInt32 = 0xEFCD_AB89
        private var h2: UInt32 = 0x98BA_DCFE
        private var h3: UInt32 = 0x1032_5476
        private var h4: UInt32 = 0xC3D2_E1F0
        private var buffer = [UInt8]()
        private var bitCount: UInt64 = 0

        mutating func update(_ data: Data) {
            bitCount += UInt64(data.count) * 8
            buffer.append(contentsOf: data)
            while buffer.count >= 64 {
                compress(Array(buffer.prefix(64)))
                buffer.removeFirst(64)
            }
        }

        mutating func finalize() -> Data {
            buffer.append(0x80)
            while buffer.count % 64 != 56 {
                buffer.append(0)
            }
            var length = bitCount.bigEndian
            withUnsafeBytes(of: &length) { buffer.append(contentsOf: $0) }
            while buffer.count >= 64 {
                compress(Array(buffer.prefix(64)))
                buffer.removeFirst(64)
            }
            var out = Data()
            out.reserveCapacity(20)
            for word in [h0, h1, h2, h3, h4] {
                var be = word.bigEndian
                withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
            }
            return out
        }

        private mutating func compress(_ block: [UInt8]) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                w[i] = UInt32(block[i * 4]) << 24
                    | UInt32(block[i * 4 + 1]) << 16
                    | UInt32(block[i * 4 + 2]) << 8
                    | UInt32(block[i * 4 + 3])
            }
            for i in 16..<80 {
                w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }
            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32)
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                let temp = rotate(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotate(b, 30)
                b = a
                a = temp
            }
            h0 &+= a
            h1 &+= b
            h2 &+= c
            h3 &+= d
            h4 &+= e
        }

        private func rotate(_ value: UInt32, _ bits: UInt32) -> UInt32 {
            (value << bits) | (value >> (32 - bits))
        }
    }
}
