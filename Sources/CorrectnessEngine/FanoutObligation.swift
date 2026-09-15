// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import WireFormat

enum FanoutObligation {
    static func destination(
        id: String,
        metric: MetricID,
        expectedRecords: Int,
        scope: DestinationExportScope?
    ) throws -> BatchDestination {
        let snapshot = try scope ?? DestinationExportScope(
            destinationID: id,
            metrics: [metric],
            startInclusive: Date(timeIntervalSince1970: 0)
        )
        return BatchDestination(
            destinationID: DestinationID(rawValue: id),
            expectedRecords: expectedRecords,
            scopeSnapshot: snapshot,
            scopeDigest: digest(snapshot)
        )
    }

    static func settle(
        receipt: DeliveryReceipt,
        destinationID: String,
        on tx: any StateTransaction
    ) throws -> DeliverySettlement {
        try tx.recordDelivery(receipt)
        return try tx.settleDelivery(
            DestinationDeliveryReceipt(
                deliveryID: DeliveryID(
                    batchID: receipt.batchID,
                    destinationID: DestinationID(rawValue: destinationID)
                ),
                accepted: receipt.accepted,
                unconfirmed: receipt.unconfirmed
            )
        )
    }

    private static func digest(_ scope: DestinationExportScope) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let encoded = (try? encoder.encode(scope)) ?? Data()
        return ContentSHA256.hex(encoded)
    }
}
