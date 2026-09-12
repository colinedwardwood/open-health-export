// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import FileWriteKit
import Foundation

/// R-25 local-folder test: open → write canary → read back → confirm bytes.
public enum LocalFileDestinationTest {
    public static func run(
        directory: URL,
        canary: Data = Data("ohe-canary\n".utf8),
        onProgress: DestinationTestProgress? = nil
    ) throws -> DestinationTestReport {
        let total = 4
        var steps: [DestinationTestStepReport] = []
        var isDirectory: ObjCBool = false
        onProgress?(1, total, .openFolder)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .failed(at: .openFolder)
        }
        steps.append(DestinationTestStepReport(name: .openFolder, outcome: .passed))

        let file = directory.appendingPathComponent("ohe-canary.ndjson")
        onProgress?(2, total, .writeCanary)
        do {
            try FileWriteKit.writeAtomically(canary, to: file)
        } catch {
            return .failed(at: .writeCanary, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .writeCanary, outcome: .passed))

        onProgress?(3, total, .readBack)
        let read: Data
        do {
            read = try Data(contentsOf: file)
        } catch {
            return .failed(at: .readBack, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .readBack, outcome: .passed))

        onProgress?(4, total, .confirmBytes)
        guard read == canary else {
            return .failed(at: .confirmBytes, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .confirmBytes, outcome: .passed))
        return DestinationTestReport(verdict: .passed, steps: steps)
    }
}
