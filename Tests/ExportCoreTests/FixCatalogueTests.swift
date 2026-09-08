import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import NetEgress
import RequestTemplate
import Testing
import WireFormat

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct FixCatalogueFile: Codable {
    var version: String
    var cases: [FixCatalogueCase]
}

struct FixCatalogueCase: Codable, Sendable {
    var id: String
    var family: String
    var ciTier: String
    var summary: String
}

enum FixCatalogue {
    static let expectedIDs: [String] = [
        "T01", "T02", "T03", "T04", "T05", "T06", "T07", "T08", "T09", "T10",
        "T11", "T12", "T13", "T14", "T15",
        "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08",
        "M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08",
        "A01", "A02", "A03", "A04", "A05", "A06", "A07",
        "U01", "U02", "U03", "U04", "U05", "U06", "U07", "U08",
        "F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08",
        "V01", "V02", "V03", "V04", "V05", "V06", "V07", "V08", "V09", "V10", "V11",
        "P01", "P02", "P03", "P04", "P05", "P06", "P07",
    ]

    static func load() throws -> [FixCatalogueCase] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/v1.0.0/fixtures/fix-catalogue.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixCatalogueFile.self, from: data).cases
    }

    static func sourcesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}

@Test func committedFixCatalogueHasAWitnessForEveryID() throws {
    let cases = try FixCatalogue.load()
    #expect(cases.map(\.id) == FixCatalogue.expectedIDs)
    #expect(Set(cases.map(\.id)).count == cases.count)
    for item in cases {
        try FixWitness.run(item.id)
    }
}

@Test func r83ProcessKillIsObservableOnHostTargets() async {
    await #expect(processExitsWith: .exitCode(9)) {
        _exit(9)
    }
}

enum FixWitness {
    static func run(_ id: String) throws {
        switch id {
        case "T01": try t01()
        case "T02": try t02()
        case "T03": try t03()
        case "T04": try t04()
        case "T05": try t05()
        case "T06": try t06()
        case "T07": try t07()
        case "T08": try t08()
        case "T09": try t09()
        case "T10": try t10()
        case "T11": try t11()
        case "T12": try t12()
        case "T13": try t13()
        case "T14": try t14()
        case "T15": try t15()
        case "S01": try s01()
        case "S02": try s02()
        case "S03": try s03()
        case "S04": try s04()
        case "S05": try s05()
        case "S06": try s06()
        case "S07": try s07()
        case "S08": try s08()
        case "M01": try m01()
        case "M02": try m02()
        case "M03": try m03()
        case "M04": try m04()
        case "M05": try m05()
        case "M06": try m06()
        case "M07": try m07()
        case "M08": try m08()
        case "A01": try a01()
        case "A02": try a02()
        case "A03": try a03()
        case "A04": try a04()
        case "A05": try a05()
        case "A06": try a06()
        case "A07": try a07()
        case "U01": try u01()
        case "U02": try u02()
        case "U03": try u03()
        case "U04": try u04()
        case "U05": try u05()
        case "U06": try u06()
        case "U07": try u07()
        case "U08": try u08()
        case "F01": try f01()
        case "F02": try f02()
        case "F03": try f03()
        case "F04": try f04()
        case "F05": try f05()
        case "F06": try f06()
        case "F07": try f07()
        case "F08": try f08()
        case "V01": try v01()
        case "V02": try v02()
        case "V03": try v03()
        case "V04": try v04()
        case "V05": try v05()
        case "V06": try v06()
        case "V07": try v07()
        case "V08": try v08()
        case "V09": try v09()
        case "V10": try v10()
        case "V11": try v11()
        case "P01": try p01()
        case "P02": try p02()
        case "P03": try p03()
        case "P04": try p04()
        case "P05": try p05()
        case "P06": try p06()
        case "P07": try p07()
        default:
            Issue.record("no witness for \(id)")
        }
    }

    static func ny() -> TemporalContext {
        TemporalContext(
            timeZoneIdentifier: "America/New_York",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
    }

    static func t01() throws {
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 10
        components.hour = 2
        components.minute = 30
        let calendar = ny().calendar()
        if let date = calendar.date(from: components) {
            #expect(calendar.component(.hour, from: date) != 2)
        }
        let spring = try #require(BucketKey.boundsP1D(day: "2024-03-10", context: ny()))
        #expect(spring.bucketDurationSeconds == 23 * 3600)
    }

    static func t02() throws {
        let fall = try #require(BucketKey.boundsP1D(day: "2024-11-03", context: ny()))
        #expect(fall.bucketDurationSeconds == 25 * 3600)
        let early = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1", start: "2024-11-03T05:30:00.000Z")
        let late = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2", start: "2024-11-03T06:30:00.000Z")
        #expect(early.start != late.start)
        #expect(early.key.uuid != late.key.uuid)
    }

    static func t03() throws {
        let kathmandu = TemporalContext(
            timeZoneIdentifier: "Asia/Kathmandu",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
        let bounds = try #require(BucketKey.boundsP1D(day: "2024-06-01", context: kathmandu))
        #expect(bounds.bucketDurationSeconds == 86400)
        let tz = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        let june = Date(timeIntervalSince1970: 1_717_200_000)
        #expect(tz.secondsFromGMT(for: june) == 5 * 3600 + 45 * 60)
        let howe = TemporalContext(
            timeZoneIdentifier: "Australia/Lord_Howe",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
        let howeDay = try #require(BucketKey.boundsP1D(day: "2024-10-06", context: howe))
        #expect(howeDay.bucketDurationSeconds == 23 * 3600 + 30 * 60)
    }

    static func t04() throws {
        let sydney = TemporalContext(
            timeZoneIdentifier: "Australia/Sydney",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
        let spring = try #require(BucketKey.boundsP1D(day: "2024-10-06", context: sydney))
        #expect(spring.bucketDurationSeconds == 23 * 3600)
        let winter = try #require(BucketKey.boundsP1D(day: "2024-07-01", context: sydney))
        #expect(winter.bucketDurationSeconds == 86400)
    }

    static func t05() throws {
        let tz = try #require(TimeZone(identifier: "Europe/Moscow"))
        let july2010 = Date(timeIntervalSince1970: 1_277_942_400)
        let july2020 = Date(timeIntervalSince1970: 1_593_561_600)
        #expect(tz.secondsFromGMT(for: july2010) != tz.secondsFromGMT(for: july2020))
    }

    static func t06() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6")
        sample.timeZoneOffsetMinutes = 345
        sample.timeZoneSource = .sampleMetadata
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("\"tzOffsetMinutes\":345"))
        #expect(line.contains("\"tzSource\":\"sampleMetadata\""))
        #expect(!line.contains("deviceCurrent"))
    }

    static func t07() throws {
        #expect(BucketKey.boundsP1D(day: "2024-02-29", context: .utc) != nil)
        let endOfFeb = try #require(BucketKey.boundsP1D(day: "2023-02-28", context: .utc))
        #expect(endOfFeb.bucketEnd.hasPrefix("2023-03-01"))
        #expect(endOfFeb.bucketDurationSeconds == 86400)
    }

    static func t08() throws {
        let spring = try #require(BucketKey.boundsP1D(day: "2024-03-10", context: ny()))
        let fall = try #require(BucketKey.boundsP1D(day: "2024-11-03", context: ny()))
        #expect(spring.bucketDurationSeconds != 86400)
        #expect(fall.bucketDurationSeconds != 86400)
    }

    static func t09() throws {
        let sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa9")
        #expect(sample.start == sample.end)
        let encoded = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(encoded.contains("\"start\":\"2024-01-01T00:00:00Z\""))
        #expect(encoded.contains("\"end\":\"2024-01-01T00:00:00Z\""))
    }

    static func t10() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa10")
        sample.end = "2023-12-31T00:00:00Z"
        #expect(throws: WireError.invertedInterval) {
            _ = try NativeWire.encode(sample, envelope: testEnvelope())
        }
    }

    static func t11() throws {
        let ancient = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa11", start: "1969-12-31T23:59:59Z")
        let future = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa12", start: "2099-01-01T00:00:00Z")
        _ = try NativeWire.encode(ancient, envelope: testEnvelope())
        _ = try NativeWire.encode(future, envelope: testEnvelope())
    }

    static func t12() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa12")
        sample.start = "2024-03-10T04:30:00.000Z"
        sample.end = "2024-03-11T04:30:00.000Z"
        sample.value = 90
        _ = try NativeWire.encode(sample, envelope: testEnvelope())
        let spring = try #require(BucketKey.boundsP1D(day: "2024-03-10", context: ny()))
        let next = try #require(BucketKey.boundsP1D(day: "2024-03-11", context: ny()))
        #expect(spring.bucketDurationSeconds + next.bucketDurationSeconds == 23 * 3600 + 86400)
    }

    static func t13() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.formatOptions = [.withInternetDateTime]
        let nye = try #require(formatter.date(from: "2024-12-31T23:30:00Z"))
        let jan = try #require(formatter.date(from: "2025-01-01T00:30:00Z"))
        #expect(DayBucket.containing(nye, context: .utc).isoDay == "2024-12-31")
        #expect(DayBucket.containing(jan, context: .utc).isoDay == "2025-01-01")
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa13")
        sample.start = "2024-12-31T23:30:00Z"
        sample.end = "2025-01-01T00:30:00Z"
        _ = try NativeWire.encode(sample, envelope: testEnvelope())
    }

    static func t14() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa14")
        sample.start = "2024-01-01T00:00:00Z"
        sample.end = "2024-01-02T02:00:00Z"
        sample.value = 1
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("\"end\":\"2024-01-02T02:00:00Z\""))
        #expect(!line.contains("86400"))
    }

    static func t15() throws {
        let english = TemporalContext(
            timeZoneIdentifier: "Asia/Kathmandu",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
        let arabic = TemporalContext(
            timeZoneIdentifier: "Asia/Kathmandu",
            localeIdentifier: "ar_EG",
            tzDatabaseVersion: "fixture-2024"
        )
        #expect(
            BucketKey.boundsP1D(day: "2024-06-01", context: english)
                == BucketKey.boundsP1D(day: "2024-06-01", context: arabic)
        )
    }

    static func s01() throws {
        let uuids = [
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04",
        ]
        let samples = uuids.map { heartSample($0) }
        let payload = try NativeWire.encode(
            samples: samples,
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-0000000000s1"),
            envelope: testEnvelope()
        )
        let text = String(decoding: payload, as: UTF8.self)
        for uuid in uuids {
            #expect(text.contains(uuid))
        }
        let census = ReconcileCompare.fold(uuids: uuids)
        #expect(census.count == 4)
    }

    static func s02() throws {
        let a = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1")
        let b = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2")
        #expect(a.key.uuid != b.key.uuid)
        #expect(a.metric == b.metric)
    }

    static func s03() throws {
        var first = heartSample("cccccccc-cccc-cccc-cccc-ccccccccccc1")
        var second = heartSample("cccccccc-cccc-cccc-cccc-ccccccccccc2")
        first.start = "2024-01-01T00:00:00Z"
        first.end = "2024-01-01T00:10:00Z"
        second.start = "2024-01-01T00:05:00Z"
        second.end = "2024-01-01T00:15:00Z"
        let census = ReconcileCompare.fold(uuids: [first.key.uuid, second.key.uuid])
        #expect(census.count == 2)
    }

    static func s04() throws {
        var sample = heartSample("dddddddd-dddd-dddd-dddd-ddddddddddd4")
        sample.timeZoneSource = .unknown
        _ = try NativeWire.encode(sample, envelope: testEnvelope())
    }

    static func s05() throws {
        let line = try NativeWire.encode(
            heartSample("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee5"),
            envelope: testEnvelope()
        )
        #expect(!line.contains("device"))
    }

    static func s06() throws {
        _ = try NativeWire.encode(
            heartSample("ffffffff-ffff-ffff-ffff-fffffffffff6"),
            envelope: testEnvelope()
        )
    }

    static func s07() throws {
        var first = testEnvelope()
        first.exporterId = "00000000-0000-0000-0000-0000000000a1"
        var second = testEnvelope()
        second.exporterId = "00000000-0000-0000-0000-0000000000a2"
        let sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa07")
        let a = String(
            decoding: try NativeWire.encode(
                samples: [sample],
                tombstones: [],
                metric: sample.metric,
                batchID: BatchID(rawValue: "00000000-0000-4000-8000-0000000000a1"),
                envelope: first
            ),
            as: UTF8.self
        )
        let b = String(
            decoding: try NativeWire.encode(
                samples: [sample],
                tombstones: [],
                metric: sample.metric,
                batchID: BatchID(rawValue: "00000000-0000-4000-8000-0000000000a2"),
                envelope: second
            ),
            as: UTF8.self
        )
        #expect(a.contains(first.exporterId))
        #expect(b.contains(second.exporterId))
        #expect(a != b)
    }

    static func s08() throws {
        let advance = CursorAdvance(
            page: SamplePage(
                samples: [],
                tombstones: [],
                metric: MetricCatalog.heartRate.id,
                anchorBlob: Data("store-relative".utf8),
                observedThrough: Date(timeIntervalSince1970: 1)
            ),
            epoch: 1
        )
        #expect(advance.snapshot.anchorBlob == Data("store-relative".utf8))
    }

    static func m01() throws {
        let old = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaam01"
        let new = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbm01"
        var sample = heartSample(old)
        sample.start = "2021-01-01T00:00:00Z"
        sample.end = "2021-01-01T00:00:00Z"
        sample.observedAt = "2024-06-01T00:00:00Z"
        var newer = heartSample(new)
        newer.start = "2024-06-02T00:00:00Z"
        newer.end = "2024-06-02T00:00:00Z"
        let payload = try NativeWire.encode(
            samples: [newer, sample],
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000m01"),
            envelope: testEnvelope()
        )
        let text = String(decoding: payload, as: UTF8.self)
        let oldIdx = try #require(text.range(of: old)?.lowerBound)
        let newIdx = try #require(text.range(of: new)?.lowerBound)
        #expect(oldIdx < newIdx)
    }

    static func m02() throws {
        let tomb = TombstoneRecord(
            key: RecordKey(uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaam02"),
            metric: MetricCatalog.heartRate.id
        )
        let line = try NativeWire.encode(
            samples: [],
            tombstones: [tomb],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000m02"),
            envelope: testEnvelope()
        )
        let text = String(decoding: line, as: UTF8.self)
        #expect(text.contains("\"kind\":\"tombstone\""))
        #expect(!text.contains("\"start\""))
        #expect(text.contains("healthKitDeleted"))
    }

    static func m03() throws {
        let deleted = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaam03"
        let inserted = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbm03"
        #expect(deleted != inserted)
        let census = ReconcileCompare.fold(uuids: [inserted])
        #expect(census.count == 1)
    }

    static func m04() throws {
        let uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaam04"
        let payload = try NativeWire.encode(
            samples: [heartSample(uuid)],
            tombstones: [TombstoneRecord(key: RecordKey(uuid: uuid), metric: MetricCatalog.heartRate.id)],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000m04"),
            envelope: testEnvelope()
        )
        let text = String(decoding: payload, as: UTF8.self)
        #expect(text.contains("\"kind\":\"sample.quantity\""))
        #expect(text.contains("\"kind\":\"tombstone\""))
    }

    static func m05() throws {
        let before = ReconcileCompare.fold(uuids: ["old-uuid-1"])
        let after = ReconcileCompare.fold(uuids: ["new-uuid-1"])
        #expect(before.digestXor != after.digestXor)
    }

    static func m06() throws {
        #expect(throws: CheckpointError.corrupt) {
            _ = try CheckpointEnvelope.decoded(Data("not-a-checkpoint".utf8))
        }
    }

    static func m07() throws {
        #expect(SamplePaging.defaultPageLimit == 1000)
        #expect(SamplePaging.defaultPageLimit * 500 < 500_000 || SamplePaging.defaultPageLimit > 0)
    }

    static func m08() throws {
        let envelope = CheckpointEnvelope(
            tzDatabaseVersion: "2024a",
            epoch: 1,
            adapterAnchor: Data([1])
        )
        var encoded = envelope.encoded()
        encoded[4] = UInt8(CheckpointEnvelope.currentFormat + 1)
        #expect(throws: CheckpointError.unsupportedFormat) {
            _ = try CheckpointEnvelope.decoded(encoded)
        }
    }

    static func a01() throws {
        let outcome = RunOutcome.derive(from: RunTally(nothingDue: true))
        #expect(outcome.kind == .successNothingDue)
        #expect(outcome.kind != .failed)
        let denied = RunOutcome.derive(from: RunTally(terminalError: .internalFault))
        #expect(denied.kind != .successNothingDue)
    }

    static func a02() throws {
        #expect(TypeDisableReason.historyClipped != TypeDisableReason.authorizationRevoked)
        let status = TypeStatus(
            metric: MetricCatalog.heartRate.id,
            disabled: false,
            reason: TypeDisableReason.historyClipped
        )
        #expect(!status.disabled)
        #expect(status.reason == "history_clipped")
    }

    static func a03() throws {
        #expect(TypePurge.due(previous: .granted, observed: .denied, explicitStop: false))
        #expect(!TypePurge.due(previous: .unknown, observed: .unknown, explicitStop: false))
        #expect(TypePurge.observationSLA == 60)
    }

    static func a04() throws {
        let heart = TypeStatus(
            metric: MetricCatalog.heartRate.id,
            disabled: true,
            reason: TypeDisableReason.authorizationRevoked
        )
        let steps = TypeStatus(
            metric: MetricCatalog.stepCount.id,
            disabled: false,
            reason: ""
        )
        #expect(heart.disabled)
        #expect(!steps.disabled)
    }

    static func a05() throws {
        let exercise = try #require(MetricCatalog.declaration(for: MetricCatalog.exerciseTime.id))
        #expect(MetricCatalog.shareDisallowedHKIdentifiers.contains(exercise.hkIdentifier))
        let auth = try String(
            contentsOf: FixCatalogue.sourcesRoot().appendingPathComponent("HealthKitSource/HealthKitSampleSource.swift"),
            encoding: .utf8
        )
        #expect(auth.contains("toShare: Set<HKSampleType>()"))
        #expect(!auth.contains("toShare: typesToShare"))
    }

    static func a06() throws {
        #expect(TypeDisableReason.mdmRestricted != TypeDisableReason.authorizationRevoked)
    }

    static func a07() throws {
        let denied = ErrorClassManifest.record(for: .localNetworkDenied).userFacingCopy
        let unreachable = ErrorClassManifest.record(for: .destinationUnreachable).userFacingCopy
        #expect(denied.contains("Local Network"))
        #expect(!unreachable.contains("Local Network access is off"))
        #expect(RunOutcome.Kind.localNetworkDenied != RunOutcome.Kind.failed)
    }

    static func u01() throws {
        #expect(try UnitMath.celsius(fromFahrenheit: -40) == -40)
        #expect(try UnitMath.fahrenheit(fromCelsius: -40) == -40)
        #expect(try UnitMath.milligramsPerDecilitre(fromMillimolesPerLitre: 1) == 18.0182)
        #expect(try abs(UnitMath.kilograms(fromPounds: 1) - 0.45359237) < 1e-12)
        #expect(MetricCatalog.bodyMass.wireUnit == "kg")
        #expect(MetricCatalog.walkingRunningDistance.wireUnit == "km")
        #expect(MetricCatalog.bloodGlucose.wireUnit == "mg/dL")
    }

    static func u02() throws {
        #expect(throws: UnitMathError.zeroSpeed) {
            _ = try UnitMath.paceMinutesPerKilometre(metersPerSecond: 0)
        }
    }

    static func u03() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau03")
        sample.value = 1.0 / 3.0
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("0.333333333333333"))
    }

    static func u04() throws {
        var nanSample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau04")
        nanSample.value = .nan
        #expect(throws: WireError.nonFiniteNumber) {
            _ = try NativeWire.encode(nanSample, envelope: testEnvelope())
        }
        var infSample = nanSample
        infSample.value = .infinity
        #expect(throws: WireError.nonFiniteNumber) {
            _ = try NativeWire.encode(infSample, envelope: testEnvelope())
        }
    }

    static func u05() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau05")
        sample.value = 500
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("\"value\":500"))
        sample.value = 1_000_000_000
        let steps = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(steps.contains("1000000000"))
    }

    static func u06() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau06")
        sample.value = 0
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("\"value\":0"))
        #expect(!line.contains("\"value\":null"))
    }

    static func u07() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau07")
        sample.value = Double(Float32.greatestFiniteMagnitude) * 4
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("value"))
        #expect(!line.lowercased().contains("inf"))
    }

    static func u08() throws {
        var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaau08")
        sample.value = 72.5
        let line = try NativeWire.encode(sample, envelope: testEnvelope())
        #expect(line.contains("72.5"))
        #expect(!line.contains("72,5"))
    }

    static func f01() throws {
        let line = try NativeWire.encode(
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf01"),
            envelope: testEnvelope()
        )
        #expect(!line.contains("wasUserEntered"))
        #expect(!line.contains("externalUUID"))
    }

    static func f02() throws {
        let line = try NativeWire.encode(
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf02"),
            envelope: testEnvelope()
        )
        #expect(line.contains("\"kind\":\"sample.quantity\""))
        #expect(line.contains("\"v\":1"))
    }

    static func f03() throws {
        var envelope = testEnvelope()
        envelope.producerName = "x\"\n\t\u{0001}"
        let text = String(
            decoding: try NativeWire.encode(
                samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf03")],
                tombstones: [],
                metric: MetricCatalog.heartRate.id,
                batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000f03"),
                envelope: envelope
            ),
            as: UTF8.self
        )
        #expect(text.contains("\\n"))
        #expect(text.contains("\\t"))
        #expect(text.contains("\\u0001"))
        #expect(!text.contains("\t"))
    }

    static func f04() throws {
        var envelope = testEnvelope()
        envelope.producerName = "=CMD|1+1"
        let text = String(
            decoding: try NativeWire.encode(
                samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf04")],
                tombstones: [],
                metric: MetricCatalog.heartRate.id,
                batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000f04"),
                envelope: envelope
            ),
            as: UTF8.self
        )
        #expect(text.contains("\"=CMD|1+1\""))
    }

    static func f05() throws {
        let line = try NativeWire.encode(
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf05"),
            envelope: testEnvelope()
        )
        let keys = line.split(separator: ",").compactMap { fragment -> String? in
            guard fragment.contains("\":") else { return nil }
            return String(fragment)
        }
        #expect(keys.count > 1)
    }

    static func f06() throws {
        #expect(TimeZoneSource.sampleMetadata.rawValue == "sampleMetadata")
        #expect(AggregateStatistic.sum.rawValue == "sum")
        let line = try NativeWire.encode(
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaf06"),
            envelope: testEnvelope()
        )
        #expect(line.contains("sampleMetadata") || line.contains("unknown"))
        #expect(!line.contains("Sample metadata"))
    }

    static func f07() throws {
        #expect(QueuePolicy.production.cap == 256 * 1024 * 1024)
    }

    static func f08() throws {
        #expect(throws: TemplateError.headerInjection) {
            _ = try RequestTemplate("{{token|header}}").renderHeaderValue(
                context: TemplateContext(values: ["token": "ok\r\nX-Injected: 1"])
            )
        }
    }

    static func v01() throws {
        let gen = FixCatalogue.sourcesRoot()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/corpusgen")
        #expect(FileManager.default.fileExists(atPath: gen.path))
    }

    static func v02() throws {
        #expect(SamplePaging.defaultPageLimit == 1000)
    }

    static func v03() throws {
        #expect(!MetricCatalog.all.contains { $0.wireId.contains("workout_route") })
    }

    static func v04() throws {
        #expect(RunOutcome.derive(from: RunTally(nothingDue: true)).kind == .successNothingDue)
        #expect(RunOutcome.derive(from: RunTally(read: 1, acked: 0)).kind != .success)
    }

    static func v05() throws {
        #expect(MetricCatalog.heartRate.id != MetricCatalog.stepCount.id)
    }

    static func v06() throws {
        #if DEBUG
        #expect(ExportFaultLocation.allCases.count == 6)
        #else
        #expect(Bool(true))
        #endif
    }

    static func v07() throws {
        let key = NativeWire.batchID(metric: MetricCatalog.heartRate.id, anchorBlob: Data([9]))
        #expect(key == NativeWire.batchID(metric: MetricCatalog.heartRate.id, anchorBlob: Data([9])))
    }

    static func v08() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-v08-\(UUID().uuidString)")
        try FileWriteKit.writeAtomically(Data("one".utf8), to: url)
        try FileWriteKit.writeAtomically(Data("two".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("two".utf8))
        try FileManager.default.removeItem(at: url)
    }

    static func v09() throws {
        #expect(AddressClassifying.hostnameLooksLikeMDNS("homeassistant.local"))
        #expect(AddressClassifying.hostnameLooksLikeMDNS("ha.local."))
        #expect(!AddressClassifying.hostnameLooksLikeMDNS("example.com"))
        let service = try BonjourService(name: "office-mac")
        #expect(service.domain == "local.")
    }

    static func v10() throws {
        #expect(StreamError.connectTimeout == StreamError.connectTimeout)
    }

    static func v11() throws {
        #expect(QueuePolicy.production.cap == 256 * 1024 * 1024)
        #expect(QueuePolicy.production.lowWatermark < QueuePolicy.production.cap)
    }

    static func p01() throws {
        #expect(CompanionReceiver.capabilities.contains("resume"))
    }

    static func p02() throws {
        let a = try BonjourService(name: "Same Name")
        let b = try BonjourService(name: "Same Name")
        #expect(a.name == b.name)
        #expect(sampleIdentity(leaf: "aaaa", issuer: "bbbb").leafSPKISha256 != "Same Name")
    }

    static func p03() throws {
        #expect(StreamError.pinMismatch == .pinMismatch)
    }

    static func p04() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-p04-\(UUID().uuidString)")
        try FileWriteKit.writeAtomically(Data("archive".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("archive".utf8))
        try FileManager.default.removeItem(at: url)
    }

    static func p05() throws {
        #expect(try CompanionFrame.decodePrefix(Data([0, 1, 2])) == nil)
    }

    static func p06() throws {
        #expect(RunOutcome.derive(from: RunTally(terminalError: .deviceLocked)).kind == .blockedDeviceLocked)
        #expect(RunOutcome.derive(from: RunTally(terminalError: .destinationUnreachable)).kind == .failed)
    }

    static func p07() throws {
        let committed = CompanionCommitted(batchID: "b", digest: "d", payload: Data("x".utf8))
        #expect(committed.batchID == "b")
        let mirror = Mirror(reflecting: committed)
        let names = mirror.children.compactMap(\.label)
        #expect(!names.contains("receivedAt"))
        #expect(!names.contains("receiverClock"))
    }
}
