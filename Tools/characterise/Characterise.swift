// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import MetricCatalog

@main
struct Characterise {
    static func main() throws {
        let data: Data
        if CommandLine.arguments.count > 1 {
            data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        let text = String(decoding: data, as: UTF8.self)
        let events = StoreCharacterisation.events(fromNDJSON: text)
        let report = StoreCharacterisation.report(events: events)
        FileHandle.standardOutput.write(try StoreCharacterisation.json(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
