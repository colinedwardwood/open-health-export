public struct PinningHTTPTransport: HTTPTransport {
    public var inner: any HTTPTransport
    public var pin: PinRecord

    public init(inner: any HTTPTransport, pin: PinRecord) {
        self.inner = inner
        self.pin = pin
    }

    public func identityProbe() async throws -> TLSIdentity? {
        try await inner.identityProbe()
    }

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        let observed = try await inner.identityProbe()
        do {
            try PinGate.requireMatch(observed: observed, stored: pin)
        } catch PinError.mismatch {
            throw EgressError.pinMismatch
        } catch PinError.notPinned {
            throw EgressError.pinMismatch
        }
        return try await inner.applyingPin(pin).execute(request)
    }
}
