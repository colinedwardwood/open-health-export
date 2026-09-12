// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog

enum CharacteristicConversion {
    static func identifier(for metric: MetricID) -> HKCharacteristicTypeIdentifier? {
        guard let declaration = MetricCatalog.declaration(for: metric),
              declaration.kind == "characteristic"
        else {
            return nil
        }
        return HKCharacteristicTypeIdentifier(rawValue: declaration.hkIdentifier)
    }

    static func objectType(for metric: MetricID) -> HKCharacteristicType? {
        guard let identifier = identifier(for: metric) else { return nil }
        return HKObjectType.characteristicType(forIdentifier: identifier)
    }

    static func biologicalSexName(_ value: HKBiologicalSex) -> String {
        switch value {
        case .notSet: "notSet"
        case .female: "female"
        case .male: "male"
        case .other: "other"
        @unknown default: "unrecognized"
        }
    }

    static func bloodTypeName(_ value: HKBloodType) -> String {
        switch value {
        case .notSet: "notSet"
        case .aPositive: "aPositive"
        case .aNegative: "aNegative"
        case .bPositive: "bPositive"
        case .bNegative: "bNegative"
        case .abPositive: "abPositive"
        case .abNegative: "abNegative"
        case .oPositive: "oPositive"
        case .oNegative: "oNegative"
        @unknown default: "unrecognized"
        }
    }

    static func fitzpatrickName(_ value: HKFitzpatrickSkinType) -> String {
        switch value {
        case .notSet: "notSet"
        case .I: "I"
        case .II: "II"
        case .III: "III"
        case .IV: "IV"
        case .V: "V"
        case .VI: "VI"
        @unknown default: "unrecognized"
        }
    }

    static func wheelchairName(_ value: HKWheelchairUse) -> String {
        switch value {
        case .notSet: "notSet"
        case .no: "no"
        case .yes: "yes"
        @unknown default: "unrecognized"
        }
    }

    static func activityMoveModeName(_ value: HKActivityMoveMode) -> String {
        switch value {
        case .activeEnergy: "activeEnergy"
        case .appleMoveTime: "appleMoveTime"
        @unknown default: "unrecognized"
        }
    }

    static func dateOfBirthValue(year: Int?, month: Int?, day: Int?) -> String? {
        guard let year, let month, let day, year > 0, month > 0, day > 0 else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Session-cached characteristic reads. Never an anchored query.
public final class HealthKitCharacteristicSource: CharacteristicSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let lock = NSLock()
    private var cache: [MetricID: CharacteristicRecord] = [:]

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func read(metric: MetricID, observedAt: String) async throws -> CharacteristicRecord? {
        if let cached = cached(metric) { return cached }

        guard HealthKitAvailability.isAvailable() else {
            throw HealthKitSourceError.unavailable
        }
        guard MetricCatalog.isCharacteristic(metric) else {
            throw HealthKitSourceError.unknownMetric(metric)
        }
        do {
            guard let record = try readUncached(metric: metric, observedAt: observedAt) else {
                return nil
            }
            remember(metric, record)
            return record
        } catch {
            throw HealthKitSourceError.classifiedQueryError(error)
        }
    }

    private func cached(_ metric: MetricID) -> CharacteristicRecord? {
        lock.lock()
        defer { lock.unlock() }
        return cache[metric]
    }

    private func remember(_ metric: MetricID, _ record: CharacteristicRecord) {
        lock.lock()
        defer { lock.unlock() }
        cache[metric] = record
    }

    private func readUncached(metric: MetricID, observedAt: String) throws -> CharacteristicRecord? {
        let characteristicId = MetricCatalog.declaration(for: metric)?.characteristicId
            ?? metric.rawValue
        let value: String?
        switch metric {
        case MetricCatalog.biologicalSex.id:
            value = CharacteristicConversion.biologicalSexName(try store.biologicalSex().biologicalSex)
        case MetricCatalog.bloodType.id:
            value = CharacteristicConversion.bloodTypeName(try store.bloodType().bloodType)
        case MetricCatalog.dateOfBirth.id:
            let components = try store.dateOfBirthComponents()
            value = CharacteristicConversion.dateOfBirthValue(
                year: components.year,
                month: components.month,
                day: components.day
            )
        case MetricCatalog.fitzpatrickSkinType.id:
            value = CharacteristicConversion.fitzpatrickName(
                try store.fitzpatrickSkinType().skinType
            )
        case MetricCatalog.wheelchairUse.id:
            value = CharacteristicConversion.wheelchairName(try store.wheelchairUse().wheelchairUse)
        case MetricCatalog.activityMoveMode.id:
            value = CharacteristicConversion.activityMoveModeName(
                try store.activityMoveMode().activityMoveMode
            )
        default:
            throw HealthKitSourceError.unknownMetric(metric)
        }
        guard let value else { return nil }
        return CharacteristicRecord(
            characteristicId: characteristicId,
            value: value,
            observedAt: observedAt
        )
    }
}
#endif
