### Pairing SAS after HELLO, QR, phone export path

The phone can show the confirmation code as soon as it parses the QR, because that payload
already names the Mac. The Mac cannot: it learns the phone's installation ID from HELLO.
`PairingSession` encodes that asymmetry; `CompanionTurn.peerInstallationID` is how the inbound
session surfaces it. Both sides use the same `CompanionPSK.handshakeIdentity` so the TLS 1.3
PSK handshake agrees on the identity bytes.

The Mac app renders a QR (CoreImage, app target only — not in the Linux core) and still keeps
the payload selectable. The iOS harness pastes that payload (camera scan is later), shows the
SAS, browses `_ohx-recv._tcp` for the **exact** paired name, and pushes one page through
`CompanionSink` over `NWByteStream`.

A golden test pins that the phone's immediate SAS equals the Mac's post-HELLO SAS
(`RPY5-BRGD` for the existing mixed-secret fixture).
