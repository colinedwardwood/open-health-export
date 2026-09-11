// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Security)
import Foundation
import Security

extension TLSIdentity {
    public static func fromServerTrust(_ trust: SecTrust, host: String) -> TLSIdentity? {
        guard
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let leaf = chain.first,
            let leafSPKI = try? SPKIDigest.sha256Hex(certificateDER: SecCertificateCopyData(leaf) as Data)
        else {
            return nil
        }
        let issuer = chain.dropFirst().first
        let issuerSPKI = issuer
            .flatMap { try? SPKIDigest.sha256Hex(certificateDER: SecCertificateCopyData($0) as Data) }
        return TLSIdentity(
            leafSPKISha256: leafSPKI,
            issuerSPKISha256: issuerSPKI ?? "",
            tlsVersion: "",
            cipherSuite: "",
            leafSubject: SecCertificateCopySubjectSummary(leaf) as String? ?? host,
            leafIssuer: issuer.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "",
            notBefore: "",
            notAfter: "",
            resolvedAddress: "",
            addressClass: .unknown,
            trustAnchorKind: "pin"
        )
    }
}
#endif
