#if canImport(Network)
import Foundation
import Network
import Security

enum TLSParameters {
    static func preSharedKey(_ psk: PreSharedKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv13)
        let key = psk.key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = psk.identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            security,
            key as __DispatchData,
            identity as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            security,
            tls_ciphersuite_t.AES_128_GCM_SHA256
        )
        return NWParameters(tls: tls)
    }
}
#endif
