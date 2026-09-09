import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MetricCatalog
import NetEgress
import WireFormat

@main
struct HAContract {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(
                Data("hacontract failed: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    static func run() async throws {
        guard let raw = ProcessInfo.processInfo.environment["OHE_HA_URL"] else {
            print("hacontract skipped: OHE_HA_URL is unset")
            return
        }
        let timeout = Duration.seconds(
            Int64(ProcessInfo.processInfo.environment["OHE_HA_WAIT_SECONDS"] ?? "480") ?? 480
        )
        let client = try HAClient(base: raw)
        try await client.waitUntilReady()
        let token = try await client.ensureToken()
        let cases = HAStatisticsContract.cases(exporterID: "device-1234")
        let firstValues: [String: Double] = Dictionary(
            uniqueKeysWithValues: cases.map { item in
                (item.entityID, item.statistic == "sum" ? 10.0 : 70.0)
            }
        )
        let secondValues: [String: Double] = Dictionary(
            uniqueKeysWithValues: cases.map { item in
                (item.entityID, item.statistic == "sum" ? 25.0 : 80.0)
            }
        )
        for item in cases {
            try await client.putState(
                entityID: item.entityID,
                state: firstValues[item.entityID]!,
                attributes: HAStatisticsContract.restAttributes(for: item),
                token: token
            )
        }
        try await client.putStringState(
            entityID: HAStatisticsContract.invalidMeasurementEntityID,
            state: "one",
            attributes: [
                "device_class": "enum",
                "state_class": "measurement",
                "options": ["1", "2"],
            ],
            token: token
        )
        try await Task.sleep(for: .seconds(2))
        for item in cases {
            try await client.putState(
                entityID: item.entityID,
                state: secondValues[item.entityID]!,
                attributes: HAStatisticsContract.restAttributes(for: item),
                token: token
            )
        }
        try await client.putStringState(
            entityID: HAStatisticsContract.invalidMeasurementEntityID,
            state: "two",
            attributes: [
                "device_class": "enum",
                "state_class": "measurement",
                "options": ["1", "2"],
            ],
            token: token
        )

        for item in cases {
            let snapshot = try await client.getState(entityID: item.entityID, token: token)
            guard HAStatisticsContract.entityMatches(snapshot, expected: item) else {
                FileHandle.standardError.write(
                    Data("rung 1–2 failed for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
            guard HAStatisticsContract.stateParses(snapshot, expected: secondValues[item.entityID]!) else {
                FileHandle.standardError.write(
                    Data("rung 3 precision failed for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
            let keys = Set((try await client.rawAttributes(entityID: item.entityID, token: token)).keys)
            if item.unit == nil, keys.contains("unit_of_measurement") {
                FileHandle.standardError.write(Data("\(item.entityID) leaked a null unit\n".utf8))
                exit(1)
            }
            if item.deviceClass == nil, keys.contains("device_class") {
                FileHandle.standardError.write(Data("\(item.entityID) leaked a null device_class\n".utf8))
                exit(1)
            }
            if item.stateClass == nil, keys.contains("state_class") {
                FileHandle.standardError.write(Data("\(item.entityID) leaked a null state_class\n".utf8))
                exit(1)
            }
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        var last: [String: [HAStatisticsRow]] = [:]
        while ContinuousClock.now < deadline {
            last = try await client.statistics(
                entityIDs: cases.map(\.entityID) + [HAStatisticsContract.invalidMeasurementEntityID],
                token: token
            )
            let missing = cases.filter {
                HAStatisticsContract.statisticsWouldRecord(
                    stateClass: $0.stateClass,
                    deviceClass: $0.deviceClass
                ) && (last[$0.entityID] ?? []).isEmpty
            }
            if missing.isEmpty { break }
            try await Task.sleep(for: .seconds(15))
        }
        for item in cases {
            let rows = last[item.entityID] ?? []
            let shouldRecord = HAStatisticsContract.statisticsWouldRecord(
                stateClass: item.stateClass,
                deviceClass: item.deviceClass
            )
            if shouldRecord, rows.isEmpty {
                FileHandle.standardError.write(
                    Data("rung 4: no statistics for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
            if shouldRecord,
               item.statistic == "sum",
               !rows.contains(where: { $0.sum != nil })
            {
                FileHandle.standardError.write(
                    Data("rung 4: no sum statistic for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
            if shouldRecord,
               item.statistic == "mean",
               !rows.contains(where: { $0.mean != nil })
            {
                FileHandle.standardError.write(
                    Data("rung 4: no mean statistic for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
            if !shouldRecord, !rows.isEmpty {
                FileHandle.standardError.write(
                    Data("rung 4: unexpected statistics for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
        }
        if !(last[HAStatisticsContract.invalidMeasurementEntityID] ?? []).isEmpty {
            FileHandle.standardError.write(
                Data("rung 4: enum+measurement produced statistics\n".utf8)
            )
            exit(1)
        }
        print("hacontract: \(cases.count) catalogue entities, invalid combination rejected")
    }
}

struct HAClient {
    var base: URL
    var session: URLSession

    init(base: String) throws {
        guard let url = URL(string: base) else { throw EgressError.invalidURL }
        self.base = url
        self.session = URLSession(configuration: .ephemeral)
    }

    func waitUntilReady() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while ContinuousClock.now < deadline {
            if let _ = try? await getJSON(path: "/api/onboarding", token: nil) {
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw EgressError.transport("home assistant never became ready")
    }

    func ensureToken() async throws -> String {
        if let existing = ProcessInfo.processInfo.environment["OHE_HA_TOKEN"], !existing.isEmpty {
            return existing
        }
        let onboard = try await getJSON(path: "/api/onboarding", token: nil)
        let done = onboard["onboarded"] as? Bool ?? false
        if !done {
            _ = try await postJSON(
                path: "/api/onboarding/users",
                token: nil,
                body: [
                    "client_id": clientID,
                    "name": "OHE CI",
                    "username": "ohe",
                    "password": password,
                    "language": "en",
                ]
            )
            _ = try? await postJSON(
                path: "/api/onboarding/core_config",
                token: nil,
                body: [
                    "client_id": clientID,
                    "location_name": "OHE",
                    "latitude": 0,
                    "longitude": 0,
                    "elevation": 0,
                    "currency": "USD",
                    "country": "US",
                    "timezone": "UTC",
                    "unit_system": "metric",
                ]
            )
            _ = try? await postJSON(
                path: "/api/onboarding/analytics",
                token: nil,
                body: ["client_id": clientID]
            )
            _ = try? await postJSON(
                path: "/api/onboarding/integration",
                token: nil,
                body: [
                    "client_id": clientID,
                    "redirect_uri": "\(base.absoluteString)/?auth_callback=1",
                ]
            )
        }
        return try await loginToken()
    }

    func putState(
        entityID: String,
        state: Double,
        attributes: [String: Any],
        token: String
    ) async throws {
        _ = try await postJSON(
            path: "/api/states/\(entityID)",
            token: token,
            body: [
                "state": formattedState(state),
                "attributes": attributes,
            ]
        )
    }

    func putStringState(
        entityID: String,
        state: String,
        attributes: [String: Any],
        token: String
    ) async throws {
        _ = try await postJSON(
            path: "/api/states/\(entityID)",
            token: token,
            body: [
                "state": state,
                "attributes": attributes,
            ]
        )
    }

    func getState(entityID: String, token: String) async throws -> HAEntitySnapshot {
        let object = try await getJSON(path: "/api/states/\(entityID)", token: token)
        let attributes = object["attributes"] as? [String: Any] ?? [:]
        return HAStatisticsContract.snapshot(
            from: attributes,
            state: object["state"] as? String ?? "",
            exists: true
        )
    }

    func rawAttributes(entityID: String, token: String) async throws -> [String: Any] {
        let object = try await getJSON(path: "/api/states/\(entityID)", token: token)
        return object["attributes"] as? [String: Any] ?? [:]
    }

    func statistics(entityIDs: [String], token: String) async throws -> [String: [HAStatisticsRow]] {
        let ws = HAWebSocket(base: base)
        return try await ws.statisticsDuringPeriod(entityIDs: entityIDs, token: token)
    }

    private var clientID: String { base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/" }
    private var password: String { "ohe-ci-password-1" }

    private func loginToken() async throws -> String {
        let start = try await postJSON(
            path: "/auth/login_flow",
            token: nil,
            body: [
                "client_id": clientID,
                "handler": ["homeassistant", NSNull()],
                "redirect_uri": clientID,
            ]
        )
        if let token = start["access_token"] as? String { return token }
        guard let flowID = start["flow_id"] as? String else {
            throw EgressError.transport("login flow missing flow_id")
        }
        let finished = try await postJSON(
            path: "/auth/login_flow/\(flowID)",
            token: nil,
            body: [
                "client_id": clientID,
                "username": "ohe",
                "password": password,
            ]
        )
        if let token = finished["access_token"] as? String { return token }
        guard let code = finished["result"] as? String else {
            throw EgressError.transport("login flow missing result code")
        }
        return try await tokenFromCode(code)
    }

    private func tokenFromCode(_ code: String) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code)&client_id=\(clientID)"
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String
        else {
            throw EgressError.transport("token exchange failed")
        }
        return token
    }

    private func getJSON(path: String, token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: url(path))
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw EgressError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func postJSON(path: String, token: String?, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: replacingNull(body))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw EgressError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: base) ?? base.appendingPathComponent(path)
    }

    private func formattedState(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.17g", value)
    }
}

private func replacingNull(_ object: [String: Any]) -> [String: Any] {
    object.mapValues { value in
        if value is NSNull { return NSNull() }
        return value
    }
}

struct HAWebSocket {
    var base: URL

    func statisticsDuringPeriod(entityIDs: [String], token: String) async throws -> [String: [HAStatisticsRow]] {
        #if os(Linux)
        return try await statisticsUsingPOSIX(entityIDs: entityIDs, token: token)
        #else
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw EgressError.invalidURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        guard let websocketURL = components.url else { throw EgressError.invalidURL }
        let task = URLSession(configuration: .ephemeral).webSocketTask(with: websocketURL)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let required = try await receiveJSON(task)
        guard required["type"] as? String == "auth_required" else {
            throw EgressError.transport("websocket did not request authentication")
        }
        try await sendJSON(task, object: ["type": "auth", "access_token": token])
        let authed = try await receiveJSON(task)
        guard authed["type"] as? String == "auth_ok" else {
            throw EgressError.transport("websocket auth")
        }
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-6 * 3600))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        try await sendJSON(
            task,
            object: [
                "id": 1,
                "type": "recorder/statistics_during_period",
                "start_time": start,
                "end_time": end,
                "statistic_ids": entityIDs,
                "period": "5minute",
            ]
        )
        let result = try await nextResult(task, id: 1)
        return rows(from: result, entityIDs: entityIDs)
        #endif
    }

    private func rows(
        from result: [String: Any],
        entityIDs: [String]
    ) -> [String: [HAStatisticsRow]] {
        let payload = (result["result"] as? [String: Any]) ?? [:]
        var mapped: [String: [HAStatisticsRow]] = [:]
        for id in entityIDs {
            let rawRows = payload[id] as? [[String: Any]] ?? []
            mapped[id] = rawRows.compactMap { row in
                guard let start = timestamp(row["start"]) else { return nil }
                return HAStatisticsRow(
                    start: start,
                    end: timestamp(row["end"]) ?? start,
                    mean: number(row["mean"]),
                    sum: number(row["sum"])
                )
            }
        }
        return mapped
    }

    #if os(Linux)
    private func statisticsUsingPOSIX(
        entityIDs: [String],
        token: String
    ) async throws -> [String: [HAStatisticsRow]] {
        let host = base.host ?? "127.0.0.1"
        let port = UInt16(base.port ?? 8123)
        let stream = POSIXByteStream(
            endpoint: try StreamEndpoint(host: host, port: port, usesTLS: false)
        )
        try await stream.open()
        let key = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) })
            .base64EncodedString()
        let handshake = [
            "GET /api/websocket HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ].joined(separator: "\r\n")
        try await stream.send(Data(handshake.utf8))
        var header = Data()
        while header.range(of: Data("\r\n\r\n".utf8)) == nil {
            header.append(try await stream.receive(max: 4096))
            if header.count > 16_384 {
                throw EgressError.transport("websocket handshake")
            }
        }
        guard let split = header.range(of: Data("\r\n\r\n".utf8)),
              String(decoding: header[..<split.lowerBound], as: UTF8.self)
                .contains(" 101 ")
        else {
            throw EgressError.transport("websocket upgrade rejected")
        }
        var leftover = Data(header[split.upperBound...])
        let required: [String: Any]
        do {
            required = try await nextPOSIXJSON(stream: stream, leftover: &leftover)
        } catch {
            throw EgressError.transport("auth-required frame: \(error)")
        }
        guard required["type"] as? String == "auth_required" else {
            throw EgressError.transport("websocket did not request authentication")
        }
        try await sendPOSIXJSON(
            stream: stream,
            object: ["type": "auth", "access_token": token]
        )
        let authed: [String: Any]
        do {
            authed = try await nextPOSIXJSON(stream: stream, leftover: &leftover)
        } catch {
            throw EgressError.transport("auth response: \(error)")
        }
        guard authed["type"] as? String == "auth_ok" else {
            throw EgressError.transport("websocket auth")
        }
        let start = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-6 * 3600)
        )
        let end = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(3600)
        )
        try await sendPOSIXJSON(
            stream: stream,
            object: [
                "id": 1,
                "type": "recorder/statistics_during_period",
                "start_time": start,
                "end_time": end,
                "statistic_ids": entityIDs,
                "period": "5minute",
            ]
        )
        let result: [String: Any]
        do {
            result = try await nextPOSIXResult(
                stream: stream,
                leftover: &leftover,
                id: 1
            )
        } catch {
            throw EgressError.transport("statistics response: \(error)")
        }
        await stream.close()
        return rows(from: result, entityIDs: entityIDs)
    }

    private func sendPOSIXJSON(
        stream: POSIXByteStream,
        object: [String: Any]
    ) async throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        try await stream.send(maskedFrame(payload))
    }

    private func nextPOSIXResult(
        stream: POSIXByteStream,
        leftover: inout Data,
        id: Int
    ) async throws -> [String: Any] {
        while true {
            let object = try await nextPOSIXJSON(stream: stream, leftover: &leftover)
            if object["type"] as? String == "result",
               (object["id"] as? Int ?? (object["id"] as? NSNumber)?.intValue) == id {
                return object
            }
        }
    }

    private func nextPOSIXJSON(
        stream: POSIXByteStream,
        leftover: inout Data
    ) async throws -> [String: Any] {
        while true {
            if let frame = decodeFrame(leftover) {
                leftover.removeSubrange(0 ..< frame.consumed)
                if frame.opcode == 0x9 {
                    try await stream.send(maskedFrame(frame.payload, opcode: 0xA))
                    continue
                }
                if frame.opcode == 0x8 {
                    let reason = frame.payload.count > 2
                        ? String(decoding: frame.payload.dropFirst(2), as: UTF8.self)
                        : "no reason"
                    throw EgressError.transport("websocket closed: \(reason)")
                }
                if frame.opcode == 0x1 {
                    return try JSONSerialization.jsonObject(
                        with: frame.payload
                    ) as? [String: Any] ?? [:]
                }
                continue
            }
            leftover.append(try await stream.receive(max: 4096))
        }
    }

    private func maskedFrame(_ payload: Data, opcode: UInt8 = 0x1) -> Data {
        var frame = Data([0x80 | opcode])
        let key: [UInt8] = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        if payload.count <= 125 {
            frame.append(0x80 | UInt8(payload.count))
        } else if payload.count <= 65_535 {
            frame.append(0x80 | 126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(0x80 | 127)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        }
        frame.append(contentsOf: key)
        frame.append(
            contentsOf: payload.enumerated().map { index, byte in
                byte ^ key[index % key.count]
            }
        )
        return frame
    }

    private func decodeFrame(
        _ buffer: Data
    ) -> (opcode: UInt8, payload: Data, consumed: Int)? {
        guard buffer.count >= 2 else { return nil }
        let bytes = [UInt8](buffer)
        let opcode = bytes[0] & 0x0F
        let masked = bytes[1] & 0x80 != 0
        var length = Int(bytes[1] & 0x7F)
        var offset = 2
        if length == 126 {
            guard buffer.count >= 4 else { return nil }
            length = Int(bytes[2]) << 8 | Int(bytes[3])
            offset = 4
        } else if length == 127 {
            guard buffer.count >= 10 else { return nil }
            length = bytes[2 ... 9].reduce(0) { ($0 << 8) | Int($1) }
            offset = 10
        }
        var key: [UInt8] = []
        if masked {
            guard buffer.count >= offset + 4 else { return nil }
            key = Array(bytes[offset ..< offset + 4])
            offset += 4
        }
        guard buffer.count >= offset + length else { return nil }
        var payload = Array(bytes[offset ..< offset + length])
        if masked {
            for index in payload.indices {
                payload[index] ^= key[index % key.count]
            }
        }
        return (opcode, Data(payload), offset + length)
    }
    #endif

    private func number(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func timestamp(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let epoch = number(value) else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: epoch))
    }

    private func sendJSON(
        _ task: URLSessionWebSocketTask,
        object: [String: Any]
    ) async throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: payload, encoding: .utf8) else {
            throw EgressError.transport("websocket JSON encoding")
        }
        try await task.send(.string(string))
    }

    private func nextResult(
        _ task: URLSessionWebSocketTask,
        id: Int
    ) async throws -> [String: Any] {
        while true {
            let object = try await receiveJSON(task)
            if object["type"] as? String == "result",
               (object["id"] as? Int ?? (object["id"] as? NSNumber)?.intValue) == id {
                return object
            }
        }
    }

    private func receiveJSON(
        _ task: URLSessionWebSocketTask
    ) async throws -> [String: Any] {
        let data: Data
        switch try await task.receive() {
        case .string(let string):
            data = Data(string.utf8)
        case .data(let received):
            data = received
        @unknown default:
            throw EgressError.transport("unknown websocket message")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EgressError.transport("websocket JSON decoding")
        }
        return object
    }
}
