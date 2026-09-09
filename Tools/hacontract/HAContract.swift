import Foundation
import MetricCatalog
import NetEgress
import WireFormat

@main
struct HAContract {
    static func main() async throws {
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
        try await client.putState(
            entityID: HAStatisticsContract.invalidEnergyMeasurementEntityID,
            state: 1,
            attributes: [
                "unit_of_measurement": "kWh",
                "device_class": "energy",
                "state_class": "measurement",
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
        try await client.putState(
            entityID: HAStatisticsContract.invalidEnergyMeasurementEntityID,
            state: 2,
            attributes: [
                "unit_of_measurement": "kWh",
                "device_class": "energy",
                "state_class": "measurement",
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
                entityIDs: cases.map(\.entityID) + [HAStatisticsContract.invalidEnergyMeasurementEntityID],
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
            if !shouldRecord, !rows.isEmpty {
                FileHandle.standardError.write(
                    Data("rung 4: unexpected statistics for \(item.entityID)\n".utf8)
                )
                exit(1)
            }
        }
        if !(last[HAStatisticsContract.invalidEnergyMeasurementEntityID] ?? []).isEmpty {
            FileHandle.standardError.write(
                Data("rung 4: energy+measurement produced statistics\n".utf8)
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

/// Tiny RFC 6455 client for HA's `/api/websocket`.
struct HAWebSocket {
    var base: URL

    func statisticsDuringPeriod(entityIDs: [String], token: String) async throws -> [String: [HAStatisticsRow]] {
        let host = base.host ?? "127.0.0.1"
        let port = UInt16(base.port ?? 8123)
        let stream = POSIXByteStream(endpoint: try StreamEndpoint(host: host, port: port, usesTLS: false))
        try await stream.open()
        let key = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        let handshake = """
        GET /api/websocket HTTP/1.1\r
        Host: \(host):\(port)\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(key)\r
        Sec-WebSocket-Version: 13\r
        \r
        """
        try await stream.send(Data(handshake.utf8))
        var header = Data()
        while header.range(of: Data("\r\n\r\n".utf8)) == nil {
            header.append(try await stream.receive(max: 4096))
            if header.count > 16_384 { throw EgressError.transport("websocket handshake") }
        }
        let split = header.range(of: Data("\r\n\r\n".utf8))!
        var leftover = Data(header[split.upperBound...])
        _ = try await nextJSON(stream: stream, leftover: &leftover)
        try await sendJSON(stream: stream, object: ["type": "auth", "access_token": token])
        let authed = try await nextJSON(stream: stream, leftover: &leftover)
        guard authed["type"] as? String == "auth_ok" else {
            throw EgressError.transport("websocket auth")
        }
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-6 * 3600))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        try await sendJSON(
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
        let result = try await nextResult(stream: stream, leftover: &leftover, id: 1)
        await stream.close()
        let payload = (result["result"] as? [String: Any]) ?? [:]
        var mapped: [String: [HAStatisticsRow]] = [:]
        for id in entityIDs {
            let encoded = try JSONSerialization.data(
                withJSONObject: ["id": 1, "type": "result", "success": true, "result": [id: payload[id] ?? []]]
            )
            mapped[id] = try HARecorder.parseWebSocketResult(encoded, entityID: id)
        }
        return mapped
    }

    private func sendJSON(stream: POSIXByteStream, object: [String: Any]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        try await stream.send(mask(payload))
    }

    private func nextResult(
        stream: POSIXByteStream,
        leftover: inout Data,
        id: Int
    ) async throws -> [String: Any] {
        while true {
            let object = try await nextJSON(stream: stream, leftover: &leftover)
            if object["type"] as? String == "result",
               (object["id"] as? Int ?? (object["id"] as? NSNumber)?.intValue) == id {
                return object
            }
        }
    }

    private func nextJSON(stream: POSIXByteStream, leftover: inout Data) async throws -> [String: Any] {
        while true {
            if let frame = try decodeFrame(leftover) {
                leftover.removeSubrange(0 ..< frame.consumed)
                if frame.opcode == 0x9 {
                    try await stream.send(pong(frame.payload))
                    continue
                }
                if frame.opcode == 0x1 {
                    return try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] ?? [:]
                }
                continue
            }
            leftover.append(try await stream.receive(max: 4096))
        }
    }

    private func pong(_ payload: Data) -> Data {
        mask(payload, opcode: 0xA)
    }

    private func mask(_ payload: Data, opcode: UInt8 = 0x1) -> Data {
        var header = Data()
        header.append(0x80 | opcode)
        let maskKey: [UInt8] = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        let length = payload.count
        if length <= 125 {
            header.append(0x80 | UInt8(length))
        } else if length <= 65535 {
            header.append(0x80 | 126)
            header.append(UInt8((length >> 8) & 0xFF))
            header.append(UInt8(length & 0xFF))
        } else {
            header.append(0x80 | 127)
            var big = UInt64(length).bigEndian
            withUnsafeBytes(of: &big) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: maskKey)
        var masked = [UInt8](payload)
        for i in masked.indices {
            masked[i] ^= maskKey[i % 4]
        }
        header.append(contentsOf: masked)
        return header
    }

    private func decodeFrame(_ buffer: Data) throws -> (opcode: UInt8, payload: Data, consumed: Int)? {
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
            length = bytes[2...9].reduce(0) { ($0 << 8) | Int($1) }
            offset = 10
        }
        var maskKey = [UInt8](repeating: 0, count: 4)
        if masked {
            guard buffer.count >= offset + 4 else { return nil }
            maskKey = Array(bytes[offset ..< offset + 4])
            offset += 4
        }
        guard buffer.count >= offset + length else { return nil }
        var payload = Array(bytes[offset ..< offset + length])
        if masked {
            for i in payload.indices { payload[i] ^= maskKey[i % 4] }
        }
        return (opcode, Data(payload), offset + length)
    }
}
