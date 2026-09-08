import CoreDomain
import Foundation
import MetricCatalog

/// Seeded synthetic samples shared by `corpusgen` (R-82) and demo mode (R-114).
public enum DemoCorpus {
    public static let sources: [SampleSourceIdentity] = [
        SampleSourceIdentity(
            name: "Synthetic Apple Watch",
            bundleIdentifier: "com.apple.health.synthetic.watch",
            productType: "Watch6,18"
        ),
        SampleSourceIdentity(
            name: "Synthetic iPhone",
            bundleIdentifier: "com.apple.health.synthetic.phone",
            productType: "iPhone17,1"
        ),
        SampleSourceIdentity(
            name: "Synthetic CGM",
            bundleIdentifier: "org.openhealthexporter.synthetic.cgm"
        ),
        SampleSourceIdentity(
            name: "Synthetic Scale",
            bundleIdentifier: "org.openhealthexporter.synthetic.scale"
        ),
        SampleSourceIdentity(
            name: "Synthetic Workout App",
            bundleIdentifier: "org.openhealthexporter.synthetic.workout"
        ),
        SampleSourceIdentity(
            name: "Synthetic Manual Entry",
            bundleIdentifier: "com.apple.Health",
            productType: "manual"
        ),
    ]

    public static func sample(
        at index: Int,
        seed: UInt64,
        declaration: MetricDeclaration
    ) -> SampleRecord {
        let random = splitMix64(UInt64(index) &+ seed)
        let year = 2020 + (index / (12 * 28)) % 6
        let month = 1 + (index / 28) % 12
        let day = 1 + index % 28
        let hour = Int((random >> 8) % 24)
        let minute = Int((random >> 16) % 60)
        let timestamp = String(
            format: "%04d-%02d-%02dT%02d:%02d:00Z",
            year, month, day, hour, minute
        )
        let uuid = String(
            format: "%08x-0000-4000-8000-%012llx",
            index & 0xFFFF_FFFF,
            random & 0xFFFF_FFFF_FFFF
        )
        let value = Double(random % 100_000) / 100
        let sourceIndex = (index / max(MetricCatalog.all.count, 1)) % sources.count
        let source = sources[sourceIndex]
        return SampleRecord(
            key: RecordKey(uuid: uuid),
            metric: declaration.id,
            start: timestamp,
            end: timestamp,
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: value,
            unit: declaration.canonicalUnit,
            observedAt: timestamp,
            source: source,
            device: SampleDevice(
                name: source.name,
                manufacturer: "Synthetic",
                model: "fixture-\(sourceIndex + 1)",
                softwareVersion: "1.0"
            ),
            wasUserEntered: sourceIndex == sources.count - 1
        )
    }

    public static func splitMix64(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
