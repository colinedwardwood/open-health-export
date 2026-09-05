import Foundation

/// Public digest helper so other L2 codecs (CompanionWire) share one first-party SHA-256.
public enum ContentSHA256 {
    public static func bytes(_ data: Data) -> Data { SHA256.hash(data) }
    public static func hex(_ data: Data) -> String { SHA256.hex(data) }
    public static func digest(_ data: Data) -> String { "sha256:" + hex(data) }
}

/// FIPS 180-4 SHA-256. First-party so ExportCore stays free of Swift packages.
enum SHA256 {
    static func hash(_ data: Data) -> Data {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalize()
    }

    static func hex(_ data: Data) -> String {
        hash(data).map { String(format: "%02x", $0) }.joined()
    }

    struct Hasher {
        private var state: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) = (
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        )
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
            out.reserveCapacity(32)
            for word in [state.0, state.1, state.2, state.3, state.4, state.5, state.6, state.7] {
                var be = word.bigEndian
                withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
            }
            return out
        }

        private mutating func compress(_ block: [UInt8]) {
            let k: [UInt32] = [
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
            ]
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = UInt32(block[i * 4]) << 24
                    | UInt32(block[i * 4 + 1]) << 16
                    | UInt32(block[i * 4 + 2]) << 8
                    | UInt32(block[i * 4 + 3])
            }
            for i in 16..<64 {
                let s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = state.0
            var b = state.1
            var c = state.2
            var d = state.3
            var e = state.4
            var f = state.5
            var g = state.6
            var h = state.7
            for i in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                h = g
                g = f
                f = e
                e = d &+ t1
                d = c
                c = b
                b = a
                a = t1 &+ t2
            }
            state.0 &+= a
            state.1 &+= b
            state.2 &+= c
            state.3 &+= d
            state.4 &+= e
            state.5 &+= f
            state.6 &+= g
            state.7 &+= h
        }

        private func rotate(_ value: UInt32, _ bits: UInt32) -> UInt32 {
            (value >> bits) | (value << (32 - bits))
        }
    }
}
