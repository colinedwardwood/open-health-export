// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import DestinationTrust
import Foundation
import WireFormat

/// R-25 companion test: hello → offer canary → receipt.
public enum CompanionDestinationTest {
    public static func run(
        pipe: any CompanionBytePipe,
        installationID: String,
        canary: Data,
        batchID: String = "canary"
    ) async -> DestinationTestReport {
        var steps: [DestinationTestStepReport] = []
        let session = CompanionSession(pipe: pipe)
        do {
            try await session.send(.hello(
                protocolVersion: CompanionReceiver.protocolVersion,
                installationID: installationID,
                capabilities: CompanionReceiver.capabilities
            ))
            let hello = try await session.receive()
            guard case .hello(let version, _, _) = hello,
                  version == CompanionReceiver.protocolVersion
            else {
                return .failed(at: .connect)
            }
            steps.append(DestinationTestStepReport(name: .connect, outcome: .passed))
            steps.append(DestinationTestStepReport(name: .confirmCertificate, outcome: .passed))
        } catch {
            return .failed(at: .connect)
        }

        let digest = ContentSHA256.digest(canary)
        let offer = CompanionOffer(
            batchID: batchID,
            idempotencyKey: batchID,
            byteCount: UInt64(canary.count),
            digest: digest
        )
        do {
            try await session.send(.offer(offer))
            switch try await session.receive() {
            case .receipt(let id, let acked) where id == batchID && acked == digest:
                steps.append(DestinationTestStepReport(name: .sendCanary, outcome: .passed))
                steps.append(DestinationTestStepReport(name: .readResponse, outcome: .passed))
                return DestinationTestReport(verdict: .passed, steps: steps)
            case .resume(let fromChunk) where fromChunk == 0:
                try await session.send(.chunk(seq: 0, bytes: canary))
                guard case .chunkAck(seq: 0) = try await session.receive() else {
                    return .failed(at: .sendCanary, prior: steps)
                }
                try await session.send(.commit(digest: digest))
                guard case .receipt(let id, let acked) = try await session.receive(),
                      id == batchID, acked == digest
                else {
                    return .failed(at: .readResponse, prior: steps)
                }
                steps.append(DestinationTestStepReport(name: .sendCanary, outcome: .passed))
                steps.append(DestinationTestStepReport(name: .readResponse, outcome: .passed))
                return DestinationTestReport(verdict: .passed, steps: steps)
            default:
                return .failed(at: .sendCanary, prior: steps)
            }
        } catch {
            return .failed(at: .sendCanary, prior: steps)
        }
    }
}
