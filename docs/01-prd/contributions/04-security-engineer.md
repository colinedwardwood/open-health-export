# Senior Security Engineer — Stage 1 Contribution

> Stage 1 artifact. Everything here is a **requirement** with an acceptance criterion, or a
> **finding** that constrains requirements. No design, no schemas, no Swift.
> Regulatory statements are cited and current as of **2 September 2026**. Where I could not
> verify a fact, I say so explicitly rather than guessing.

---

## Executive summary

This product is a scheduled, unattended, network-egress pipeline for Article 9 special-category
data, operated by the data subject. Functionally it is indistinguishable from an exfiltration
tool; the only thing that makes it legitimate is that the data subject chose the destination.
**Therefore the single highest-value security property in this product is not confidentiality of
the transport — it is the user's ability to know, verify and audit exactly where their data
went.** A perfectly TLS-secured export to the wrong host is a total loss. Most of my Must
requirements are consequences of that sentence.

Six findings that change the product, not just harden it:

1. **A listening TCP server on iOS launders HealthKit authorisation and I will not sign off on
   it for v1.** Any other app on the device can reach `127.0.0.1:<port>` with no permission
   prompt whatsoever — network access is not a gated capability on iOS, whereas HealthKit read
   access is. A localhost listener therefore converts Apple's consent gate into a
   no-permission-required read for every other app on the device, and plausibly makes us
   "disclose to third parties" health data under App Review 5.1.3(i). The LAN exposure story is
   bad; the localhost story is disqualifying. See §3.

2. **Apple 5.1.3(ii) states flatly that apps "may not store personal health information in
   iCloud."** [1] This is a contractual condition of distribution, not folklore. It puts the
   reference product's iCloud Drive destination, any CloudKit sync of health data, and any
   health payload sitting in an un-excluded container that iCloud Backup sweeps up, into direct
   conflict with App Review. This is a **hard constraint that removes advertised
   reference-product functionality from our roadmap** unless the PM accepts review risk. See §6
   and SEC-30/31.

3. **HIPAA does not apply to us. Do not put it on a compliance checklist.** We are not a covered
   entity and not a business associate, because nobody engages us to handle PHI on their behalf
   [3][4][5]. The regime that *does* create a live US obligation is the **FTC Health Breach
   Notification Rule**, amended effective 29 July 2024 specifically to reach non-HIPAA health
   apps [6][7][8]. See §6.

4. **Whether the EU Cyber Resilience Act binds us is a decision the PM/user makes by choosing a
   monetisation model, not a fact about the code.** Free, unmonetised, published by a natural
   person → outside CRA scope entirely. Published by a legal entity → "open-source software
   steward", light-touch Article 24 duties, no fines. Charge any price, or gate binaries/updates
   behind donations → **manufacturer**, with the full Annex I regime, SBOM, CE marking and
   24h/72h/14d incident reporting [9][10][11][12]. Manufacturer reporting duties begin
   **11 September 2026 — nine days from now**; full obligations 11 December 2027 [12][13]. See §6.

5. **I am vetoing the majority of a conventional OpenTelemetry deployment.** A trace of this
   pipeline is health data: span attributes carry sample types (a `bloodGlucose` span
   identifies a diabetic), destination hostnames identify clinics, and error strings carry
   payload fragments. My veto is not a principle, it is a **CI-enforced attribute allow-list**
   plus **no first-party collector, ever**. See §7.

6. **Bit-for-bit verification that the App Store binary matches our source is impossible on iOS**
   and I will not permit us to claim otherwise. Apple FairPlay-encrypts and re-signs every App
   Store binary [23][24][25]. What is achievable is signed build provenance plus an
   App-Store-independent, hash-verifiable macOS build. See §8.

The premise is sound. My objections are to three specific things in it: the listening server,
the observability posture as currently framed, and any iCloud destination.

---

## Threat model

### Methodology, and why

I use **LINDDUN as the primary lens, with STRIDE as a secondary sweep.** Justification:

- The dominant loss event in this product is **not** a security compromise, it is a *legitimate
  mechanism operating correctly toward an illegitimate recipient*. STRIDE has no category for
  that. LINDDUN's **Disclosure of information**, **Unawareness** and **Non-compliance**
  categories address it head-on, and its **Linkability / Identifiability / Detectability**
  categories capture the metadata harms that matter here (an export schedule reveals sleep
  patterns; a destination hostname reveals a clinic; packet timing on a LAN reveals that a
  health app is running at all).
- STRIDE remains necessary because we do have classic security boundaries — a listening socket,
  a Keychain, a build pipeline. Threats T-20…T-33 are STRIDE-derived.
- Neither framework covers the **coercive-insider** case (§ T-24), which is a first-class threat
  for health data and which I am adding explicitly. This is a documented gap in both
  methodologies, not an oversight in them.

**Assumption (mine, labelled):** we operate no server-side infrastructure of any kind in v1. If
that assumption breaks, this entire threat model must be re-run, because it changes our
regulatory status under GDPR, HBNR, MHMDA and CCPA simultaneously.

### Assets

| ID | Asset | Sensitivity |
|---|---|---|
| A1 | HealthKit sample values (150+ types: ECG, glucose, medications, sleep, cycle tracking, workouts+GPS) | GDPR Art 9 special category; the crown jewels |
| A2 | Destination credentials: API tokens, OAuth refresh tokens, MQTT passwords, TLS client identities | Compromise → silent ongoing exfiltration by a third party |
| A3 | Destination configuration: URLs, hostnames, ports, topics | **Itself health data by inference** (`mqtt.oncology-clinic.example`) |
| A4 | Queued / cached / partially-delivered export payloads on device | A1 outside HealthKit's protection domain — our weakest link |
| A5 | Telemetry: traces, spans, structured logs, crash reports | A1 + A3 by leakage; see §7 |
| A6 | Export history and schedule metadata | Behavioural inference; also the audit record that defends the user |
| A7 | Release signing identity, App Store Connect account, CI secrets | Compromise → malicious update to every user |
| A8 | Source repository, `Package.resolved`, transitive dependency graph | Public by design; attacker reads it too |
| A9 | HealthKit authorisation grants held by our app | The capability an attacker wants to borrow |
| A10 | The user's egress ledger (§4/SEC-11) | Tamper-evidence for everything above |

### Trust boundaries

| ID | Boundary | Enforced by |
|---|---|---|
| TB1 | HealthKit store → our process | OS authorisation, per-type, user-granted |
| TB2 | Our process → app container storage | Data Protection classes, file keys |
| TB3 | Our process → Keychain / Secure Enclave | `kSecAttrAccessible*`, access control lists |
| TB4 | **Our process → network → user-chosen destination** | TLS + our own verification UX. *The critical boundary.* |
| TB5 | Our process ↔ LAN / localhost peers | Local Network permission [15][16]; **nothing else by default** |
| TB6 | Our process → OS shared surfaces: pasteboard, share sheet, notifications, Files, app-switcher snapshot, Spotlight | Per-surface, largely our responsibility |
| TB7 | Device → iCloud Backup / Finder backup / iCloud Keychain | Backup exclusion flags, `ThisDeviceOnly` accessibility |
| TB8 | Our process → any telemetry sink | §7. Default: closed |
| TB9 | Source → CI → signed artifact → App Store / GitHub Releases → device | Branch protection, provenance, notarisation |
| TB10 | Our process ↔ other apps on device (URL schemes, App Groups, XPC, AppleEvents, localhost) | Our responsibility; **most-underestimated boundary** |

### Actors

Legitimate: the user/data subject (who is also the operator, and therefore also the most likely
source of catastrophic misconfiguration); self-hosters; maintainers.

Adversarial: a malicious or later-compromised destination operator; a passive or active network
attacker (café Wi-Fi, hostile ISP, state-level interception); a co-resident app on the device; a
person with physical device access (thief, border officer, employer, **intimate partner**); a
malicious contributor or a compromised upstream dependency maintainer; a browser-based attacker
using DNS rebinding to reach a local listener; and ourselves, through error.

Involuntary observers: Apple, the user's DNS resolver, the destination's hosting provider, and
anyone on the path who can see TLS SNI or traffic volume.

### Threat table

| ID | Threat | Actor | Impact | Likelihood | Required mitigation |
|---|---|---|---|---|---|
| **T-01** | User configures a destination with a typo'd or wrong hostname; every scheduled export silently ships their health record to a stranger, indefinitely | User (error) | Catastrophic, irreversible, ongoing | **High** — the single most likely real-world loss event | SEC-09 canary handshake, SEC-10 identity confirmation, SEC-11 egress ledger, SEC-12 dry-run preview |
| **T-02** | Destination operator is honest at setup, is later compromised or sold; exports continue unchanged | Destination operator | Total disclosure of A1 | Medium | SEC-13 pin-on-first-use + halt-on-change; SEC-11; SEC-16 data minimisation per destination |
| **T-03** | Destination is malicious from the outset (a "free health dashboard" that harvests) | Destination operator | Total disclosure | Medium | SEC-12 preview, SEC-14 public-destination typed confirmation, SEC-16; documentation, not code, is the main defence — flag to PM |
| **T-04** | DNS hijack / rebinding redirects a previously-verified hostname to attacker infrastructure | Network attacker | Total disclosure | Medium | SEC-13 (SPKI pin), SEC-15 connect-time address-class re-check |
| **T-05** | TLS interception by an enterprise/state MITM proxy whose CA is in the system trust store | Network attacker | Total disclosure, invisible to user | Medium | SEC-13 pinning defeats system-trust MITM; SEC-19 no ATS weakening |
| **T-06** | Downgrade / stripping to plaintext against a self-hoster's HTTP endpoint | Network attacker on LAN | Disclosure | Medium | SEC-19–SEC-22 (the private-CA/plaintext resolution, §5) |
| **T-07** | Passive traffic analysis: SNI, packet sizes, export timing reveal health-app usage and activity patterns even under TLS | Network attacker | Detectability / inference | High (unavoidable) | SEC-23 padding + jitter as *Should*; honest documentation. **I do not claim to solve this.** |
| **T-08** | Unauthenticated LAN reader hits our listening TCP server on café Wi-Fi | Network attacker | Total disclosure of A1 | **High if shipped** | **SEC-01: do not ship it in v1** (§3) |
| **T-09** | Bonjour/mDNS advertisement removes even the need to port-scan; the app announces "health data here" | Network attacker | Targeting + detectability | High if shipped | SEC-01; SEC-04 no advertisement before pairing |
| **T-10** | DNS-rebinding attack from a web page the user visits reaches the local listener without the attacker being on the LAN at all | Browser-based attacker | Total disclosure | Medium if shipped | SEC-01; SEC-05 Host/Origin validation if ever shipped |
| **T-11** | **Another app on the device reads all health data via `127.0.0.1`, holding no HealthKit permission**, bypassing TB1 entirely | Co-resident app | Total disclosure + authorisation bypass + App Review violation | **High if shipped** | **SEC-01. This is the disqualifying finding.** (§3) |
| **T-12** | Co-resident app or web page adds an exfiltration destination via our URL scheme / universal link / config-file import | Co-resident app | Total ongoing disclosure | Medium | SEC-17 no non-interactive destination mutation; SEC-18 signed-config import requires typed confirmation |
| **T-13** | macOS XPC / AppleEvents surface lets an unprivileged local process query health data | Co-resident process | Disclosure | Medium | SEC-24 client code-signature validation; SEC-25 no scriptable health accessors |
| **T-14** | Health values legible in the app-switcher snapshot, in a Lock Screen notification, or in a Lock Screen widget | Physical access | Disclosure to shoulder-surfer | High | SEC-26 snapshot obscuring, SEC-27 notification content ban, SEC-28 widget redaction |
| **T-15** | Device passcode known to a partner/employer; app opened, destinations and history read | Physical access | Disclosure + enables T-24 | Medium | SEC-29 optional app-level biometric gate that does **not** gate background export |
| **T-16** | Queued health payloads swept into iCloud Backup or an encrypted Finder backup, then restored elsewhere | Backup/restore | Disclosure; **also 5.1.3(ii) violation** | High if unmitigated | SEC-30 backup exclusion, SEC-31 no iCloud storage of A1, SEC-32 Data Protection classes |
| **T-17** | Destination credentials migrate to a new device via backup or iCloud Keychain, and the new holder inherits live exfiltration capability | Backup/restore | A2 compromise | Medium | SEC-33 `…ThisDeviceOnly` default; SEC-34 sync only as explicit opt-in |
| **T-18** | Crash report or diagnostic log contains a payload fragment, token, or clinic hostname and is transmitted off-device | Us (error) | Disclosure | **High** — this is how it usually happens | SEC-35–SEC-40 (§7); SEC-41 no third-party crash SDK |
| **T-19** | Log file readable via Files app, or included in a sysdiagnose the user emails to support | Us (error) | Disclosure | Medium | SEC-42 log content ban + SEC-30 exclusion + SEC-43 redaction-by-construction |
| **T-20** | Credential or health data placed on the general pasteboard, readable by other apps / Universal Clipboard | Us (error) | Disclosure | Medium | SEC-44 pasteboard rules |
| **T-21** | Share-sheet export writes A1 outside our Data Protection domain to an arbitrary third-party app | User + us | Disclosure | Medium | SEC-45 one-time warning; SEC-46 share sheet never used for scheduled export |
| **T-22** | Malicious contributor lands a subtle egress change (an extra destination, a widened telemetry attribute) in a large PR | Contributor | Total disclosure of all users' A1 | Low probability, extreme impact | SEC-47 CODEOWNERS on egress-critical paths, SEC-48 two-approval + signed commits, SEC-37 allow-list diff is reviewable |
| **T-23** | Compromised dependency version, or a dependency that adds its own telemetry SDK | Upstream maintainer | Disclosure / RCE | Medium | SEC-49–SEC-52 dependency policy |
| **T-24** | **Coercive insider** (abusive partner, controlling parent, employer with MDM) configures a destination on the victim's device to monitor pregnancy, cycle-tracking or mental-health data | Coercive insider | Severe physical-safety harm | Medium, and severe | SEC-11 non-hideable egress ledger, SEC-53 local notification on every new destination, SEC-54 destinations can never be hidden from the UI |
| **T-25** | CI secret or signing identity exfiltrated; malicious signed update pushed to all users | Attacker on TB9 | Complete loss for all users | Low, catastrophic | SEC-55–SEC-59 release integrity |
| **T-26** | Tag/branch-based GitHub Action mutated upstream to steal secrets | Attacker on TB9 | A7 compromise | Medium | SEC-56 actions pinned to full commit SHA |
| **T-27** | Repudiation: user cannot prove, and we cannot show, what was sent where and when — after an incident | Us (design gap) | Non-compliance; no incident forensics | High if unmitigated | SEC-11 append-only local egress ledger |
| **T-28** | We ship telemetry to a first-party collector, becoming a GDPR controller of Art 9 data and a WA MHMDA regulated entity with a private right of action attached | Us | Regulatory exposure; contradicts premise | Medium (drift) | **SEC-36 Won't: no first-party collector in v1** |
| **T-29** | Nutrition label / privacy manifest inaccurate relative to actual behaviour → App Review rejection or removal | Us | Distribution loss | Medium | SEC-60 label derived from an enumerated egress inventory, re-verified per release |
| **T-30** | Elevation via ATS weakening: a debug `NSAllowsArbitraryLoads` ships to production | Us (error) | All TLS guarantees void | Medium | SEC-19 build-time assertion on shipped `Info.plist` |
| **T-31** | Tampering with the on-device queue by a jailbroken-device attacker to inject false HealthKit writes | Local attacker | Integrity; 5.1.3(ii) false-data violation | Low | SEC-61 no write-back to HealthKit in v1 |
| **T-32** | Denial of service: unbounded retry against a dead destination drains battery and holds A1 on disk indefinitely | Destination / error | Availability + prolonged A4 exposure | Medium | SEC-62 bounded queue with TTL and hard cap |
| **T-33** | Feature creep into interpretation ("your HRV suggests AF") turns the app into a regulated medical device | Us (product drift) | Regulatory; distribution loss | Medium | SEC-63 explicit non-interpretation boundary |

---

## Attack surface assessment: the listening server and LAN protocols

The reference product ships a built-in TCP server for direct data reads. Assessed honestly:

### What an attacker on the same café Wi-Fi gets

If the listener is unauthenticated and bound to all interfaces, the answer is: **everything.**
A `/24` sweep of the DHCP range on a single TCP port, or simply listening for the mDNS
advertisement, yields a complete health record — ECG, medications, cycle tracking, sleep,
workout GPS traces. No exploit, no credential, no user interaction. Client isolation on public
Wi-Fi is a courtesy, not a guarantee, and is absent on most hotel, conference and home networks.
Bonjour makes this *easier* than port-scanning: the device volunteers its presence and service
type [15]. A hostile network operator additionally sees traffic timing and volume for every
export regardless of the listener.

### The disqualifying finding: localhost launders HealthKit consent

This is the argument that decides it, and it is independent of the LAN entirely.

On iOS, **making outbound network connections is not a permission-gated capability.** Reading
HealthKit **is** — per-type, user-granted, revocable, and Apple's central privacy control for
this data class. A listening socket on `127.0.0.1` means any other app on the device — including
one that has never requested and would never be granted HealthKit access — can obtain the user's
complete health record with an ordinary socket connection and no prompt.

That is a privilege-escalation service for every other app on the device. It also puts us
squarely against App Review 5.1.3(i), which prohibits disclosing HealthKit-gathered data to
third parties [1]: we would be operating an unauthenticated disclosure endpoint by design.
Note that the Local Network permission does **not** help here — it governs local *network*
access, and loopback traffic from a co-resident app is not our permission to grant or withhold.

### Secondary: DNS rebinding

If the listener speaks HTTP, an attacker does not need to be on the network at all. A web page
the user visits can re-resolve an attacker-controlled hostname to `192.168.x.x` or `127.0.0.1`
and issue requests that the browser considers same-origin. This class of attack has repeatedly
broken local-listener designs in desktop and mobile software. Defence requires strict `Host`
header allow-listing, rejection of requests bearing a browser `Origin`, and authentication —
all three, not one.

### Additional platform reality

iOS provides no background execution mode for a general-purpose TCP listener. A listener is
therefore foreground-or-suspended, which makes it both unreliable for its stated purpose *and*
an incentive for users to keep the app foregrounded and the phone unlocked — worsening T-14 and
T-15. On macOS, by contrast, a persistent listener is architecturally ordinary.

### What would be required to make it defensible

If it ships at all, **all** of the following, not a subset:

1. Mutual TLS, or a bearer token of ≥128 bits of entropy, provisioned out-of-band (QR/pairing
   code). No default credential, no derived-from-device-name credential.
2. Self-generated server certificate whose SPKI fingerprint the client pins at pairing.
3. Off by default; foreground-only on iOS; visible in-app indicator whenever listening;
   automatic shutdown after an idle timeout and on backgrounding.
4. No Bonjour advertisement until at least one client is paired.
5. Bound to non-cellular interfaces only; **explicitly refuse loopback connections**, or
   authenticate them identically — there is no way to attribute a loopback peer to a specific
   app, which is precisely why T-11 cannot be mitigated, only avoided.
6. `Host` allow-list, rejection of `Origin`-bearing requests, and per-peer rate limiting.
7. Every served request appended to the egress ledger (SEC-11).

Even with all seven, T-11 remains unmitigated. Requirement 5 is not satisfiable.

### Recommendation

**Do not ship a listening server on iOS/iPadOS/watchOS in v1** (SEC-01). The product's own
push-export mechanism already serves the stated use case: the data reaches the user's own
endpoint, initiated by us, over TLS we verify, recorded in the ledger. A pull server is a second,
strictly worse path to the same outcome.

Reconsider a listener for **macOS only**, post-v1, behind all seven controls above (SEC-02).
macOS has a real background story, a real firewall UX, and no loopback-laundering equivalence
problem of the same severity, because macOS apps are not gated on HealthKit in the same way and
the threat model there is genuinely different. That is a Stage 2+ conversation.

I will state this plainly for the record: **an unauthenticated or default-on listening server on
iOS is something I will not sign off on at any stage.**

---

## Credential and secret handling requirements

### Storage class, and the background-execution tension nobody expects

The obvious answer — `kSecAttrAccessibleWhenUnlocked` — is **wrong for this product**, because
scheduled exports must run while the device is locked. `WhenUnlocked` items are unreadable then,
so exports would fail exactly when they are supposed to work [18][19].

The correct default is **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** (SEC-33):

- `AfterFirstUnlock` → readable by our background task after the user's first post-boot unlock,
  which is the actual operating condition.
- `ThisDeviceOnly` → **not** synced to iCloud Keychain and **not** restorable to a different
  device from a backup [18][19][20]. This directly kills T-17.

The cost, stated honestly: a user restoring to a new iPhone must re-enter every destination
credential. That is the correct trade for a secret whose compromise yields silent, ongoing
exfiltration of a health record, and it must be **surfaced in the UI before setup**, not
discovered during a migration (SEC-64).

`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` is stronger still — it refuses to store if no
passcode is set, and is deleted if the passcode is removed [18][19] — but it behaves as
`WhenUnlocked` and therefore breaks background export. Use it for the **credential-reveal**
path only (SEC-65), not for the export path.

### Secure Enclave: what it can and cannot do here

Be precise, because this is routinely overclaimed. The Secure Enclave stores and operates on
**P-256 keys it generated itself**. It cannot store a bearer token, an OAuth refresh token or an
MQTT password, and **an externally-supplied private key — such as the one inside a user's
PKCS#12 TLS client identity — cannot be imported into it.**

Therefore:

- **Applicable (SEC-66, Should):** generate a non-exportable SE-backed P-256 key and use it to
  wrap the symmetric key that encrypts the credential blob and the on-device queue. This adds
  hardware device-binding on top of Keychain protection, so a stolen container is useless off
  the originating device.
- **Applicable (SEC-67, Should):** where a destination supports it, offer an SE-generated client
  key for mutual TLS, with the CSR exported for the self-hoster to sign. This gives self-hosters
  a genuinely non-exfiltratable client credential.
- **Not applicable:** user-supplied client identities. These land in the Keychain at
  `AfterFirstUnlockThisDeviceOnly` with `kSecAttrSynchronizable` false. Do not claim SE
  protection for them (SEC-68).
- **Not applicable:** biometric gating (`.userPresence`) on any credential used by scheduled
  export. It is definitionally incompatible with unattended operation. Gate the *UI reveal*, not
  the export (SEC-65).

### Should credentials sync via iCloud Keychain? Both sides.

**For:** iCloud Keychain is end-to-end encrypted, HSM-backed, and Apple cannot read it [21].
Users own multiple Apple devices and expect configuration to follow them; forcing manual
re-entry of a long API token on four devices produces the real-world outcome of users pasting
tokens into Notes, or choosing weaker credentials, or abandoning the app. Refusing to sync
pushes the secret into worse containers.

**Against:** syncing multiplies the number of devices from which silent exfiltration can
continue. It widens the blast radius of a single compromised Apple ID from one device to all of
them, and — decisively for T-24 — a coercive insider with access to the shared Apple ID
inherits working credentials on their own hardware. It also removes the `ThisDeviceOnly`
protection that makes T-17 non-exploitable, since `kSecAttrSynchronizable: true` is *mutually
exclusive* with any `ThisDeviceOnly` accessibility class — the combination returns
`errSecParam` [20]. You cannot have both.

**Resolution (SEC-34):** device-local by default; iCloud Keychain sync available as an explicit,
per-destination opt-in, presented with the blast-radius consequence in plain language, and
never enabled by a migration, a "restore settings" flow, or a default. I would refuse to sign
off on sync-by-default.

### What must never reach a backup

Non-negotiable (SEC-30): queued and cached health payloads; export payload temp files; log and
trace files; OAuth refresh tokens; API tokens; MQTT passwords; TLS client private keys; the
egress ledger's raw contents if it embeds hostnames. Keychain items are handled by
`ThisDeviceOnly`; **files are not** and require explicit `NSURLIsExcludedFromBackupKey` on every
directory holding A2/A4/A5. Acceptance criterion is an actual backup inspection, not a code
review (see SEC-30).

### Credentials on app deletion

- **iOS/iPadOS:** Keychain items in the app's default access group are removed when the app is
  deleted on current OS versions. **Do not rely on this.** Items in a shared keychain access
  group or App Group can outlive the app, and behaviour has changed across OS versions.
- **macOS:** login-keychain items **persist indefinitely** after an app bundle is dragged to the
  Trash. This is a genuine divergence and a real residual-secret problem.
- **Requirement (SEC-69):** ship an explicit in-app "Delete all credentials, queued data, logs
  and history" action that is idempotent, verifiable and documented; and on macOS, additionally
  document manual Keychain removal in the uninstall instructions. Verification: enumerate the
  keychain by access group after running the action and assert zero items.
- **Requirement (SEC-70):** revoking HealthKit authorisation for a type must purge that type's
  queued payloads within 60 seconds, not merely stop future reads.

---

## Data in transit and at rest

### Baseline in transit

- TLS 1.3 preferred, **TLS 1.2 the floor**, forward secrecy required, per-destination
  (SEC-19/SEC-20).
- App Transport Security stays **enabled**. `NSAllowsArbitraryLoads`,
  `NSAllowsArbitraryLoadsForMedia` and `NSAllowsArbitraryLoadsInWebContent` must be absent or
  false in every shipped build, enforced by a release-blocking check on the built `Info.plist`
  (SEC-19). All three require written justification at App Review and invite additional
  scrutiny [14]; we will have none to give, because we should have none.
- Certificate Transparency required for publicly-trusted chains (SEC-21, Should).

### The self-hoster tension, resolved

The self-hoster with a private CA, or a plain-HTTP endpoint on their LAN, is a real user with a
real need and a real risk. Dodging this by refusing all non-public-CA endpoints would make the
product useless to its most likely audience; dodging it by shipping `NSAllowsArbitraryLoads`
would make every user's export interceptable. Neither is acceptable. Here is the concrete
resolution, in three parts.

**Part 1 — Private CA and self-signed certificates: solve with custom trust evaluation, not with
ATS exceptions (SEC-22, Must).**

This is the key technical point and it is frequently got wrong. ATS governs TLS *parameters* —
protocol version, cipher suite, forward secrecy. Server-certificate *trust* is a separate
evaluation that an app may legitimately perform itself. A user-imported CA anchor, or a
user-pinned leaf SPKI, evaluated per-destination in the app, therefore satisfies ATS without any
`Info.plist` exception at all: the connection is still TLS 1.2+ with forward secrecy; only the
trust anchor differs.

So: the self-hoster imports their CA certificate or pins their leaf, scoped to **that one
destination**, and gets full-strength TLS. No global weakening, no App Review justification, and
strictly *better* than public-CA trust because it defeats T-05 system-trust MITM. Requirements:
anchors are per-destination and never global; the anchor's fingerprint and subject are displayed
at import and re-displayed on any change; import requires interactive confirmation.

**Part 2 — Plaintext HTTP to a LAN endpoint: narrowly permitted, heavily fenced (SEC-20, Must).**

Some self-hosters genuinely run `http://homeassistant.local:8123`. Permitted **only** when every
one of these holds:

1. `NSAllowsLocalNetworking` is the **only** ATS key used. It is the correct narrow key and,
   unlike the others, **requires no App Review justification** [14].
2. The destination is a `.local` name, an unqualified hostname, or an address in a private/
   link-local range.
3. **The address class is re-checked at connect time, on every single connection** — not at
   configuration time. A hostname that resolved privately yesterday may resolve publicly today
   (T-04). If the resolved address is public, the export **fails closed** and alerts. This is
   the requirement that makes the concession safe, and it is the one most likely to be dropped
   in implementation; it is therefore an explicit acceptance criterion.
4. The user has typed a confirmation phrase for that destination, having been shown that anyone
   on their network can read the data.
5. The destination is permanently marked as insecure in the destination list and in the ledger.

Never permitted, at any priority: plaintext to a public address; TLS below 1.2; globally
disabled forward secrecy; `NSAllowsArbitraryLoads` in a shipped build.

**Open verification task for Stage 2 (flagged, not assumed):** Apple documents
`NSAllowsLocalNetworking` as covering unqualified and `.local` domains [14]. Whether it also
covers RFC 1918 IP literals must be verified empirically with `nscurl` before we promise
item 2 above. I have not verified it and will not assert it.

**Part 3 — Application-layer encryption for insecure destinations (SEC-23, Should).**

Offer optional payload encryption to a recipient public key the user supplies, so that a
plaintext or partially-trusted transport carries ciphertext. This makes the self-hoster's
concession survivable rather than merely disclosed.

### Certificate pinning: applicability, honestly

Classic pinning assumes the app author controls the server. Here the user picks arbitrary
endpoints we have never seen, so a shipped pin set is meaningless, and hard pinning would break
every certificate rotation. Conversely, we operate **no** first-party endpoints, so there is
nothing for us to pin *to* — an architectural virtue worth naming.

The applicable model is **pin-on-first-use with change alerting (SEC-13, Must):** record the
SPKI hash at the verified first connection; on any subsequent change, **halt exports to that
destination** and require explicit re-confirmation showing old and new fingerprints. This
defeats T-02, T-04 and T-05 without breaking rotation, because rotation produces a prompt rather
than a silent failure or a silent success. Optional manual SPKI pinning for advanced users
(SEC-71, Could).

### At rest

- **Queued/cached health payloads (A4):** `NSFileProtectionComplete` where the writing path
  allows; `NSFileProtectionCompleteUnlessOpen` for files a background task must create while
  locked — this is precisely that class's intended use case;
  `NSFileProtectionCompleteUntilFirstUserAuthentication` as the absolute floor.
  **`NSFileProtectionNone` is prohibited for any file containing A1, A2 or A3** (SEC-32).
- **Independent application-layer encryption (SEC-72, Must):** A4 encrypted with a key held in
  the Keychain at `AfterFirstUnlockThisDeviceOnly`, ideally SE-wrapped (SEC-66). Defence in
  depth against Data Protection misapplication, which is a common and silent implementation
  error.
- **No A1 in `UserDefaults`, `NSUserActivity`, Handoff, Spotlight indexes, state-restoration
  archives, or CloudKit** (SEC-31).
- **Bounded retention (SEC-62):** delete on successful delivery; hard TTL (proposal: 7 days,
  PM to confirm); hard queue size cap; on TTL expiry, delete and alert rather than retaining
  indefinitely. Unbounded queues are how "data stays on device" quietly becomes "a year of
  health data sits in a cache".
- **Backup exclusion (SEC-30)** on every A2/A4/A5 directory.

---

## Regulatory posture

Stated per regime as **actual obligation** or **good practice**. Where I cannot verify, I say so.

### HIPAA — does not apply. Not on the checklist.

**Obligation: none.** The analysis, rather than the assertion:

HIPAA binds **covered entities** (health plans, clearinghouses, and providers transmitting
health information in connection with a covered transaction) and their **business associates**
[4]. We are obviously not a covered entity. A business associate is one who "creates, receives,
maintains or transmits PHI **on behalf of**" a covered entity to carry out its covered functions
[4]. Nobody engages us. The user installs our app and directs their own data to their own
destination. HHS states directly that an app developer whose app is used by consumers who
populate it with their own health information is **not** a business associate, because no
covered entity has engaged them [5], and that facilitating an individual's access to their own
ePHI at that individual's request "alone does not create a business associate relationship" [3].

The Clinical Health Records case is the interesting one and lands the same way: even where data
originates from a HIPAA-covered provider, once it has been transmitted to a third-party app at
the individual's direction, that information is **no longer subject to HIPAA** in the app's hands
[3]. So even a user who imports clinical records does not pull us into HIPAA.

**The only thing that changes this (SEC-73, Must):** contracting with a covered entity to
provide the app to its patients on its behalf. We must never do that without re-running this
analysis, and the requirement is a documented prohibition on such arrangements absent a fresh
legal review.

### FTC Health Breach Notification Rule — this is the real US obligation

**Obligation: probable, and the one worth engineering for.** The FTC amended the HBNR effective
**29 July 2024** expressly to cover health apps not reached by HIPAA [6][7]. The FTC's own
guidance states that "most health apps that aren't covered by HIPAA" are in scope, because most
health-app developers act as "health care providers" furnishing health care services or supplies
— the app itself — to consumers, provided the app has the technical capacity to draw health
information from multiple sources [8]. We draw from HealthKit, which itself aggregates Watch,
iPhone, third-party apps and clinical records: multiple sources, comfortably. The amended
definition of "breach of security" explicitly includes **unauthorised disclosure**, not merely
an intrusion [7] — which means a bug that ships payloads to the wrong endpoint is plausibly a
reportable breach.

Two honest caveats. First, the Rule reaches entities engaged in commerce; whether an unmonetised
OSS project is a "vendor of personal health records" in the FTC's sense is, to my knowledge,
untested, and I cannot verify a resolution. Second, a genuinely zero-server architecture leaves
us holding nothing that can be breached.

**Requirement anyway (SEC-74, Must), because the cost is low and the alternative is unpleasant:**
we must be *capable* of notification. We deliberately have no user list, so the only feasible
mechanism is an **in-app security advisory channel** plus a published advisory. Build the channel
in v1; it is also how we meet CRA and CVD expectations. Note the design irony worth stating to
the PM: privacy-by-design deprives us of the contact details a breach-notification duty assumes.

### GDPR and UK GDPR — out of scope while we process nothing, and precisely why

**Obligation: none in the zero-telemetry architecture. Immediate and significant the moment
telemetry exists.**

Controllership requires determining the purposes and means of processing *that one carries out*.
In the v1 architecture we carry out none: HealthKit data is read on the user's device by
software running under the user's control and transmitted to a destination the user chose. No
personal data reaches us. We are therefore **neither controller nor processor** — not because an
exemption shields us, but because there is no processing by us to attach a role to. (We are also
not a processor: nobody instructs us, and we receive nothing.)

The user's own processing is covered by the **household exemption**, Art 2(2)(c) — a natural
person processing their own data for purely personal purposes [17]. Two precisions matter:

1. The household exemption is **the user's shield, not ours.** GDPR Recital 18 expressly notes
   that the Regulation still applies to controllers or processors "which provide the means for
   processing personal data for such personal or household activities" [22]. Providing the means
   does not by itself make us a controller — but it removes any argument that supplying the tool
   is itself exempt processing. Anyone claiming "household exemption" as *our* defence has
   misread it.
2. The exemption is **narrowly construed** and fails where processing is directed outward or
   made available to an indefinite number of people [17]. Irrelevant for a user exporting to
   their own server; relevant if we ever add sharing features.

**What changes the instant we add any telemetry reaching us:** we become a controller of that
telemetry. If it contains health data — and per §7, telemetry about a health pipeline trivially
does — we need an **Art 9(2)(a) explicit consent** basis, not legitimate interests, because
Art 9(1) prohibits processing special-category data outright absent an exception. Add: an Art 13
privacy notice, data-subject-rights machinery for access/erasure/portability, Art 30 records, a
likely Art 35 DPIA (large-scale special-category processing), an Art 27 EU representative if we
have no EU establishment, Art 44+ transfer analysis for wherever the collector runs, and
Art 33 72-hour breach notification. UK GDPR mirrors this with the ICO as regulator.

That is a compliance programme, for a project with no revenue, in exchange for error telemetry.
**This is the strongest single argument for SEC-36 (no first-party collector, ever).**

### CCPA / CPRA — no current obligation

**Obligation: none.** CCPA applies to a "business" meeting statutory thresholds (revenue,
consumer volume, or majority of revenue from selling personal information). An unmonetised OSS
project meets none, and independently collects no personal information. Health data is
"sensitive personal information" under CPRA, which would matter only if we collected it.

**Good practice, adopted regardless:** the CPRA posture we can honestly claim is "we do not
collect, sell or share personal information," and it should be stated in exactly those terms in
the privacy policy (SEC-75).

### US state consumer-health-data laws — the sharpest tail risk

**Obligation: none while we collect nothing; disproportionately serious if that changes.**
Washington's **My Health My Data Act** regulates any entity conducting business in or targeting
Washington consumers that collects, processes, shares or sells consumer health data, defined far
more broadly than HIPAA's PHI and expressly reaching app and wearable data. Critically, an MHMDA
violation is a **per se** violation of the Washington Consumer Protection Act, which carries a
**private right of action** — a class-action exposure no other state health-privacy law provides
[26][27][28]. Nevada SB 370 is similar in substance but is AG-enforced only, with no private
right of action [29]. Connecticut has comparable provisions. New York's Health Information
Privacy Act was vetoed in 2025 and revived in the 2026 session; **I cannot verify its status as
of today and it must be re-checked before launch** [26].

Two concrete consequences: (a) MHMDA is the highest-litigation-risk regime we could stumble into,
and it is triggered by *collection*, which reinforces SEC-36; (b) MHMDA prohibits geofencing
around in-person health-care facilities [27]. We export workout GPS. **Requirement (SEC-76,
Must):** no feature may geofence, or trigger behaviour based on proximity to, a health-care
facility. This closes a door before anyone thinks it is a clever idea.

### Apple App Store Review — binding contractual obligation, and our tightest constraint

Not law, but a condition of distribution, which makes it operationally the *most* binding regime
here. From the current guidelines [1]:

- **5.1.3(i)** — no use or disclosure of HealthKit-gathered data for advertising, marketing or
  use-based data mining; and **"You must disclose the specific health data that you are
  collecting from the device."** Reinforced by **5.1.2(vi)**, which bars HealthKit data from
  marketing/advertising/data-mining "including by third parties" [1].
- **5.1.3(ii)** — **"may not store personal health information in iCloud."** Discussed below.
- **2.5.1** — HealthKit "should be used for health and fitness purposes and integrate with the
  Health app" [1]. Our purpose qualifies; worth noting because an export-only utility invites
  the question.
- **Privacy policy and purpose strings** for each requested type, requesting only the minimum
  necessary. Over-broad HealthKit requests are a common rejection cause — directly relevant to
  us, because "150+ metrics" tempts a request-everything design. **Requirement (SEC-77, Must):**
  HealthKit authorisation requested **incrementally, per type, at the point the user configures
  an export needing it** — never a blanket up-front request for all types.
- **Privacy manifest (`PrivacyInfo.xcprivacy`) and App Privacy nutrition label**, required for
  App Store Connect submissions since May 2024, including declared reasons for any
  Required-Reason API and manifests for listed third-party SDKs [2]. Xcode merges app and SDK
  manifests; inconsistency between declared and actual behaviour risks rejection [2].
  **Requirement (SEC-60, Must):** the nutrition label is generated from an enumerated,
  reviewed **egress inventory**, and re-verified every release.

**On 5.1.3(ii), the hard part.** Apple's own Health app stores health data in iCloud with
end-to-end encryption [21], which makes the third-party prohibition read oddly — but it applies
to us, not to Apple. Three consequences:

1. **App-managed iCloud/CloudKit storage of health data is out.** An "iCloud Drive destination"
   or CloudKit-based cross-device sync of health data cannot be built as an app-managed feature.
   This removes an advertised reference-product capability from parity (SEC-31).
2. **iCloud Backup of our container is arguably "storing PHI in iCloud"** if health payloads sit
   in a backed-up directory. SEC-30's backup exclusion is thus both a security control *and* a
   review-compliance control.
3. **Ambiguous middle ground, flagged rather than resolved:** a *user-initiated* export via the
   document picker to a location the user happens to have chosen in iCloud Drive is arguably the
   user's own storage rather than the app storing PHI in iCloud. I consider that reading
   defensible but **I cannot verify how App Review treats it**, and I am not willing to have the
   PM discover the answer during a launch review. **Open question for the PM (Q3).** If we
   pursue it, we pursue it via a pre-submission enquiry to App Review, not by shipping and hoping.

### EU Cyber Resilience Act — applicability is a monetisation decision

**Obligation: depends entirely on how the project is published. This is a live 2026 issue and
the PM must decide it consciously.** Per the Commission's July 2026 CRA guidance [9] and the
Commission's OSS page [10]:

| How we publish | CRA status | What that costs us |
|---|---|---|
| Free, unmonetised, published by a **natural person** | **Out of scope entirely.** Not placed on the market; a natural person's free community version is outside CRA scope [9 §52–53][10] | Nothing |
| Free, unmonetised, published by a **legal person** (Ltd/foundation) providing sustained support for software intended for commercial activities | **Open-source software steward**, Art 24 [10][11] | Documented cybersecurity policy; cooperate with market surveillance; report actively exploited vulns and severe incidents. **Exempt from administrative fines** (Art 64(10)) [10] |
| Funded **only by voluntary donations**, binaries and updates available to everyone | Donations without profit intent are not commercial activity; "a FOSS supported only through donations is therefore unlikely to be considered to be placed on the market" [9 §61] | Nothing extra — but see next row |
| Donations that **gate** access to binaries, updates or security fixes | Donations are "de facto equivalent to charging a price" → **placed on the market → manufacturer** [9 §62, Examples 21–22] | Full regime |
| **Any price**, paid tier, or paid App Store listing | **Manufacturer** [9 §51] | Annex I essential requirements, SBOM, technical documentation, conformity assessment, CE marking, support-period security updates, and Art 14 reporting: 24h early warning, 72h notification, 14-day final report [11][12] |

Timeline: **manufacturer vulnerability/incident reporting obligations begin 11 September 2026 —
nine days from now** — with the remaining obligations applying from 11 December 2027 [12][13].

**Requirements:** SEC-78 (Must) — no price, paid tier, or donation-gated release artifact without
an explicit recorded CRA re-analysis first; the free binary and its security updates must be
available to everyone, donor or not. SEC-79 (Must) — publish a cybersecurity policy and a
CSIRT/ENISA-capable reporting path satisfying Art 24 regardless of which row we land in, since
it is cheap and it is also just good practice. SEC-80 (Should) — generate an SBOM per release
now, so that a later move to manufacturer status is not a crisis.

### EU Data Act — does not apply to us, and is an argument *for* the product

**Obligation: none.** The Data Act governs **connected products** and **related services**. Our
app is neither: a related service must be connected to a physical product such that its absence
would prevent the product performing a function, or must subsequently add to or adapt those
functions, and the Commission's FAQ requires **two-directional** data exchange with the product —
which "seems to exclude apps that merely display data received from a connected product" [30].
Guidance is explicit that an app which merely displays a product's data without controlling its
operation is not a related service [31]. We read from HealthKit and control no device.

The interesting corollary, worth handing to the PM as positioning rather than compliance: the
Data Act exists to give users access to data they co-create by using connected products such as
fitness devices [32] — which is this product's entire thesis. But the Commission also notes
that where connected-product data is stored on-device with no manufacturer access, "there is
only a user and no data holder" [30] — so the Data Act does not create a right against Apple
here either. Use it as narrative, not as a legal claim (SEC-81, Should: no regulatory-compliance
claims in marketing that we cannot substantiate).

**Not verified:** the precise application date of Data Act Chapter II. It does not affect the
conclusion, since we are out of scope on substance.

### Medical device regulation — a boundary to hold, not an obligation

**Obligation: none as scoped.** We move data; we do not interpret it for diagnostic or
therapeutic purposes. But the line is one feature away: any output that interprets health data
to suggest a condition or a clinical action risks Software-as-a-Medical-Device status under EU
MDR or FDA rules, with a compliance burden that would end this project. **Requirement (SEC-63,
Must):** no feature may interpret, diagnose, screen, alert on clinical thresholds, or recommend
clinical action; statistics and charts must be descriptive only. This is a requirement precisely
because it will be tempting later.

---

## Constraints imposed on observability

I have read the premise's "observable by design" differentiator and I agree with the goal: a
self-hoster must be able to see why an export failed. I am not vetoing observability. I am
vetoing the default shape of it, because **telemetry about a health-data pipeline is health
data**, and the standard OpenTelemetry idiom — rich span attributes, exception recording with
messages, exemplars, generous sampling — is a health-data disclosure mechanism wearing an
engineering hat.

Three worked examples, so the vetoes are not abstract:

- A span named `export.sample` with attribute `health.type = HKQuantityTypeIdentifierBloodGlucose`
  contains no values and still discloses that the user is diabetic. **Sample type identifiers are
  health data.** So are `insulinDelivery`, `menstrualFlow`, `sexualActivity`, `electrocardiogram`.
- `destination.host = mqtt.oncology.stmarys.example` discloses a cancer diagnosis. **Destination
  hostnames are health data by inference (A3).**
- `error.message = "unexpected token at 'glucose':14.2 at offset 812"` embeds a payload
  fragment. Error strings from serialisation and HTTP layers routinely carry payload bytes.

### Explicit vetoes

Each is written to be concretely reviewable — a CI job or a test can fail on it, and a reviewer
can point at a diff and say "this violates V-n".

- **V-1 (SEC-36, Won't).** **No first-party telemetry or crash collector, in v1 or ever, without
  a fresh PRD.** No project-operated OTLP endpoint, no default collector URL, no "anonymous
  usage statistics". Rationale is in §6: it converts us into a GDPR controller of Art 9 data, a
  probable WA MHMDA regulated entity with a private right of action attached, and an HBNR
  breach-notification subject with something to actually lose. **Verification:** no
  project-controlled hostname appears in any shipped configuration, asserted by a build-time
  check over the built product's strings and defaults.

- **V-2 (SEC-35, Must).** **All off-device telemetry is off by default** and requires the user to
  supply their own collector endpoint. There is no bundled default. **Verification:** a fresh
  install emits zero network traffic to any host other than a user-configured destination, shown
  by a packet capture across a full export cycle in the release test plan.

- **V-3 (SEC-37, Must).** **Span/log attribute keys are governed by a static allow-list.** The
  allow-list lives in a single reviewable file with CODEOWNERS protection; a test enumerates
  every attribute key the code can emit and **fails the build** on any key not present. This is
  the mechanism that makes the whole section enforceable rather than aspirational, and it is a
  deliberate inversion of the usual deny-list approach: **new attributes are forbidden until
  someone argues for them in a reviewable diff.**

  Permitted on the allow-list: sample **counts**, byte sizes, durations, retry counts,
  coarse-grained outcome enums, protocol names, HTTP status classes (`2xx`/`4xx`/`5xx`), TLS
  version, and an **opaque per-destination identifier** (a locally generated random ID, not a
  hash of the URL — a hash of a guessable hostname is not an anonymisation).

  Prohibited on the allow-list: any HealthKit type identifier, any sample value or unit, any
  timestamp at finer than hourly granularity for a health event, any destination hostname, URL,
  port, MQTT topic, username, header, or user-supplied label; any raw request or response body;
  any file path containing a payload; and any device/OS/build tuple combined with destination
  count (a fingerprint).

- **V-4 (SEC-38, Must).** **No exception or error object may be recorded verbatim.** Errors are
  mapped through a closed enum of project-defined codes before they reach any span or log record.
  Underlying `NSError`/`Error` descriptions, decoding-failure messages and HTTP response bodies
  are never attached to telemetry. **Verification:** unit tests assert that a serialisation
  failure over a payload containing a distinctive canary value produces telemetry not containing
  that canary. This test is the single most valuable test in the security suite; if only one
  security test survives triage, keep this one.

- **V-5 (SEC-41, Must).** **No third-party crash-reporting, analytics or session-replay SDK.**
  Named and prohibited: Sentry, Firebase/Crashlytics, Amplitude, Mixpanel, Datadog RUM,
  Bugsnag, TelemetryDeck, and equivalents. Rationale: each is an unreviewable egress path for A1
  and A5, each adds transitive supply-chain surface (T-23), each imposes privacy-manifest and
  nutrition-label consequences [2], and any of them makes our "no data reaches us" claim false.
  Apple's own opt-in crash sharing is acceptable because the user's relationship is with Apple,
  not us. **Verification:** dependency allow-list check in CI (SEC-49).

- **V-6 (SEC-42, Must).** **On-device diagnostic logs are subject to the same allow-list** as
  off-device telemetry. There is no "it's only local, so it can be verbose" tier. Local logs
  reach a Files-app browse, a `sysdiagnose` the user emails to support, an iCloud backup, and a
  forensic examiner. **Verification:** the same canary test as V-4, applied to log sinks.

- **V-7 (SEC-39, Must).** **Verbose payload-level diagnostics may exist only as an explicitly
  user-armed, time-boxed "diagnostic session"** — foreground-armed, auto-expiring within 60
  minutes, written to storage marked non-backed-up, clearly labelled as containing health data,
  and deleted at expiry. It must never be enabled by default, by a remote flag, or by an error
  condition.

- **V-8 (SEC-40, Must).** **No remote configuration of telemetry.** No feature flags fetched at
  runtime, no server-driven sampling, no dynamic log-level. Everything about telemetry must be
  determined by the shipped binary and local user settings, so that reading our source tells you
  the truth about our behaviour — which is the entire point of being open source.

- **V-9 (SEC-43, Must).** **Redaction by construction, not by filtering.** Health values must
  not be representable in a telemetry-bound type. A regex scrubber at the sink is not acceptable:
  it fails on new fields, and the failure is silent. The type system must make the unsafe thing
  unrepresentable.

### What the observability engineer still gets

I want to be constructive about the trade, because the goal is legitimate: full trace and span
structure; timings and durations; retry and backoff visibility; queue depth and age; per-
destination success/failure rates against opaque IDs; protocol-level and TLS-level outcomes;
coarse error taxonomy; and the user's own collector receiving all of it. That is enough to answer
"why did my export fail" — which was the actual requirement — without building a health-data
side channel.

**What I expect to be argued about, and my position:** requests for the HealthKit type
identifier in spans (refused — it is the diagnosis), for the destination hostname (refused — use
the opaque ID and let the user's own local UI resolve it), and for verbatim error messages
(refused — map to enums; V-4). If the PM overrides any of these, I want the override recorded in
the PRD with a named owner, because it changes our regulatory position, not just our risk
posture.

---

## Supply chain, release integrity and disclosure

### Dependency policy

- **SEC-49 (Must):** an explicit dependency **allow-list**. Adding any runtime dependency
  requires a written justification in the PR, review of its full transitive tree, and two
  maintainer approvals. CI fails on any resolved dependency absent from the allow-list. Target
  for v1: **zero third-party runtime dependencies** in the code paths that touch A1 or A2.
- **SEC-50 (Must):** all SPM dependencies pinned to exact versions with `Package.resolved`
  committed and **verified unchanged in CI**. No branch or `from:` range dependencies in a
  release manifest. Binary targets require a verified checksum, and are discouraged outright.
- **SEC-51 (Must):** prohibited dependency characteristics — bundles any analytics/telemetry
  transport; requires network access at build time; ships a binary blob without a checksum;
  carries a non-OSI licence; or has no security contact.
- **SEC-52 (Should):** automated dependency vulnerability scanning on every PR and on a weekly
  schedule, with a named owner for triage.

**Applied to the observability ask:** an OpenTelemetry Swift SDK plus an OTLP exporter plus its
protobuf/gRPC transitive tree is a large third-party surface running *inside* the process that
holds A1 and A2. That is a supply-chain argument against the current observability shape, not
merely a privacy one, and it should be weighed in Stage 2 against a much smaller
project-authored exporter.

### Malicious contributor

- **SEC-47 (Must):** CODEOWNERS on egress-critical paths — anything performing network I/O,
  Keychain access, Data Protection attribute setting, ATS configuration, the telemetry attribute
  allow-list, and destination configuration. Security-maintainer review required.
- **SEC-48 (Must):** branch protection on `main` — two approvals, no self-merge, no force-push,
  linear history, signed commits, required status checks.
- **SEC-56 (Must):** all CI actions pinned to **full commit SHAs**, never tags or branches
  (T-26); minimal `GITHUB_TOKEN` permissions; no `pull_request_target` workflows with secret
  access; no self-hosted runners in release workflows.
- **SEC-57 (Must):** maintainer accounts require hardware-backed 2FA. Release requires two
  maintainers.
- **SEC-58 (Should):** an "egress diff" step in review — any PR that changes the set of hosts,
  ports or protocols the app can talk to is labelled automatically and requires security review.
  T-22's whole premise is that a subtle egress change hides in a large diff; make it impossible
  to hide.

### Reproducible and verifiable builds — being realistic

**Finding: bit-for-bit verification that an App Store binary corresponds to published source is
not achievable on iOS.** Apple applies FairPlay encryption to App Store binaries and re-signs
them, so the artifact a user downloads cannot be reproduced without keys we do not have; code
signatures embed timestamps; App Thinning produces per-device variants. Extracting a comparable
binary requires dumping decrypted pages from memory on a jailbroken device and normalising
`LC_UUID`, `LC_CODE_SIGNATURE`, `LC_ENCRYPTION_INFO_64` and `__LINKEDIT` before comparison —
which Telegram and Immuni have both done, and which is achievable by a handful of researchers,
not by users [23][24][25].

Therefore:

- **SEC-59 (Must):** publish **signed build provenance** for every release — an attestation
  binding the uploaded artifact to the exact source commit and CI workflow, using workflow OIDC
  identity (SLSA-style, Sigstore). This is the strongest honest guarantee available on iOS: it
  proves *what we uploaded* was built from *this commit* in *this repository*, without claiming
  anything about Apple's subsequent re-encryption.
- **SEC-55 (Must):** distribute the **macOS build outside the App Store** as a Developer
  ID-signed, hardened-runtime, **notarised and stapled** artifact, with published SHA-256 hashes
  and provenance attestations, verifiable by any user with `codesign`/`spctl` and a hash check.
  macOS is where verifiability is actually attainable, so we should not squander it by being
  App-Store-only.
- **SEC-82 (Should):** publish the build environment (Xcode 26.6 / Swift 6.3.3, toolchain
  hashes) and a documented verification procedure, including the jailbreak-based iOS comparison
  path for researchers, stated with its limitations.
- **SEC-83 (Must):** **prohibit any claim of "reproducible", "verifiable" or "auditable
  binaries" for the iOS App Store build** in the README, marketing or store listing. We may
  claim auditable *source* and verifiable *provenance*. Claiming more would be exactly the kind
  of unfalsifiable privacy marketing this project exists to improve on, and **I will not sign
  off on it.**

### Disclosure

- **SEC-84 (Must):** `SECURITY.md` at repo root specifying supported versions, GitHub Private
  Vulnerability Reporting plus a dedicated security address, a PGP key or Signal contact for
  sensitive reports, an **acknowledgement SLA of 5 business days**, a **90-day coordinated
  disclosure default**, a clear in-scope/out-of-scope statement, a **safe-harbour statement**
  for good-faith research, and an explicit statement that we offer **no bounty** (better to say
  so than to imply one).
- **SEC-85 (Must):** a documented CVD process aligned with ISO/IEC 29147 (receiving reports) and
  ISO/IEC 30111 (internal handling), with named responders and a deputy. This doubles as the
  Art 24 CRA cybersecurity policy (SEC-79).
- **SEC-86 (Must):** CVE issuance for confirmed vulnerabilities via GitHub's CNA, plus published
  advisories, plus delivery through the in-app advisory channel (SEC-74) — which is our only
  route to users, given we deliberately hold no user list.
- **SEC-87 (Should):** if we land in CRA manufacturer territory (SEC-78), pre-establish the
  ENISA/national-CSIRT reporting path and rehearse the 24h/72h/14d timeline [11][12] before it
  is needed. Discovering the process during an incident is how deadlines get missed.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| SEC-01 | No listening TCP/HTTP server on iOS/iPadOS/watchOS in v1 | **Must (Won't-have feature)** | Localhost listener launders HealthKit consent to any co-resident app (T-11); unauthenticated LAN exposure (T-08) | No socket enters listening state in any build; verified by `lsof`/network-extension inspection during the release test pass |
| SEC-02 | Any future macOS listener requires all seven controls in §3 | Should | macOS listener is defensible; iOS is not | Security sign-off gate recorded in the ADR before implementation |
| SEC-03 | Local Network permission requested only when a LAN destination is configured, with an accurate purpose string | Must | Least privilege; user comprehension [15][16] | Fresh install with only a public HTTPS destination never triggers the Local Network prompt |
| SEC-04 | No Bonjour/mDNS advertisement of any health-related service | Must | Removes targeting and detectability (T-09) | No `NSBonjourServices` advertisement in shipped `Info.plist`; mDNS capture shows no advertisement |
| SEC-05 | If any HTTP listener ever ships: `Host` allow-list, reject `Origin`-bearing requests, per-peer rate limit | Must (conditional) | DNS rebinding (T-10) | Rebinding test-suite case fails closed |
| SEC-09 | Before the first real export, a destination must pass a **canary handshake**: a benign non-health payload, with the user confirming receipt | Must | Catches typo'd/wrong host before any health data moves (T-01) | Attempting a health export to an unconfirmed destination is refused; automated test asserts refusal |
| SEC-10 | At confirmation, display resolved IP, TLS version, certificate subject, issuer and SPKI fingerprint | Must | Gives the user the evidence needed to detect T-01/T-04/T-05 | UI test asserts all five fields present and non-truncated |
| SEC-11 | Append-only, on-device **egress ledger**: timestamp, destination ID and label, transport security state, sample-type categories, sample counts, byte count, outcome — for every transmission including failures | Must | The core defence for a data-exfiltration tool; addresses T-01, T-02, T-24, T-27 | A full export cycle produces exactly one matching ledger entry; ledger is user-viewable, user-exportable, and non-erasable except by the delete-all action (SEC-69) |
| SEC-12 | **Dry-run preview**: user can see the exact payload that would be sent, per destination, before enabling it | Must | Informed consent is impossible without it (T-03, T-12) | Preview byte-for-byte matches what the export path emits, asserted by test |
| SEC-13 | **Pin-on-first-use**: record destination SPKI at confirmed first connection; on change, halt exports and require explicit re-confirmation showing old and new fingerprints | Must | Defeats operator compromise, DNS hijack and system-trust MITM without breaking rotation (T-02, T-04, T-05) | Simulated certificate change halts export and raises a user-visible alert; no data is sent |
| SEC-14 | Adding a destination on a **public** address requires a typed confirmation phrase | Must | Friction proportional to irreversibility (T-03) | UI test: destination remains disabled until the phrase is entered |
| SEC-15 | Address class (private vs public) re-evaluated **at every connection**, not at configuration time; public resolution on a plaintext destination fails closed | Must | Defeats DNS re-pointing of a "LAN" destination (T-04) | Test: destination configured as `.local`, DNS re-pointed to a public address → export fails, alert raised, zero bytes sent |
| SEC-16 | Per-destination data minimisation: the user selects exactly which types and which date range go to each destination; no "export everything" default | Must | Limits blast radius of every disclosure threat; also App Review minimum-necessary expectation [1] | Default state of a new destination is zero types selected |
| SEC-17 | No destination may be created, modified or enabled by URL scheme, universal link, `NSUserActivity`, or file import without interactive user confirmation in the app | Must | Prevents co-resident app or web page from adding an exfiltration path (T-12) | Test: crafted URL scheme invocation produces a confirmation UI and no state change if dismissed |
| SEC-18 | Configuration import/export must exclude credentials by default and require typed confirmation to include them | Must | Config sharing is a credential-leak vector | Exported config file contains no secret material by default; asserted by test |
| SEC-19 | ATS enabled; `NSAllowsArbitraryLoads*` keys absent or false in every shipped build; TLS 1.2 floor with forward secrecy | Must | Prevents debug settings reaching production (T-30); avoids App Review justification burden [14] | Release-blocking CI check parses the **built** `Info.plist`; TLS floor verified with a downgrade-test server |
| SEC-20 | Plaintext HTTP permitted only under all five conditions in §5 Part 2, using `NSAllowsLocalNetworking` as the sole ATS key | Must | Serves the real self-hoster need without weakening anyone else (T-06) | Each of the five conditions has a dedicated test; plaintext to a public address is refused |
| SEC-21 | Certificate Transparency required for publicly-trusted chains | Should | Detects mis-issuance | Connection to a non-CT-logged public certificate is refused |
| SEC-22 | User-imported CA anchors and pins are **per-destination**, never global; fingerprint and subject displayed at import and on change | Must | Gives private-CA self-hosters full TLS without global weakening (§5 Part 1) | Test: anchor imported for destination A does not validate destination B |
| SEC-23 | Optional application-layer payload encryption to a user-supplied recipient key | Should | Makes plaintext/partial-trust transports survivable | Encrypted payload is undecryptable without the key; round-trip test |
| SEC-24 | macOS XPC/IPC endpoints validate client code signature (audit token + requirement string) | Must | Prevents local privilege borrowing (T-13) | Unsigned/mismatched client is rejected; test asserts rejection |
| SEC-25 | No AppleScript/AppleEvents accessors expose health data or credentials | Must | Scripting is an unauthenticated read surface (T-13) | Scripting dictionary review; no health-bearing terms |
| SEC-26 | No health values legible in the app-switcher/window snapshot | Must | Shoulder-surf and physical access (T-14) | Manual and screenshot-diff verification on backgrounding |
| SEC-27 | Notifications contain no health values, type names, or destination hostnames — outcome and count only | Must | Lock Screen exposure (T-14) | Test enumerates all notification bodies against the SEC-37 allow-list |
| SEC-28 | Widgets and Live Activities redact health values when the device is locked | Must | Lock Screen exposure (T-14) | Locked-device widget inspection |
| SEC-29 | Optional app-level biometric/passcode gate on opening the app and on viewing destinations, credentials and the ledger — which must **not** gate background export | Must | Physical access (T-15) without breaking unattended operation | Gate enabled → UI locked, scheduled export still succeeds |
| SEC-30 | Every directory holding queued payloads, caches, logs, traces or credential material is excluded from backup (`NSURLIsExcludedFromBackupKey`) | Must | Backup/restore exposure (T-16); also 5.1.3(ii) exposure [1] | **Take an actual encrypted Finder backup and an iCloud backup, enumerate contents, assert zero health payloads and zero secrets.** Code review alone is insufficient |
| SEC-31 | No app-managed storage of health data in iCloud, iCloud Drive, or CloudKit; no health data in `UserDefaults`, `NSUserActivity`, Handoff, Spotlight, or state-restoration archives | Must | App Review 5.1.3(ii) prohibition [1] | Container and entitlement audit per release; no CloudKit container holds health record types |
| SEC-32 | `NSFileProtectionNone` prohibited for any file containing health data, credentials or destination configuration; `Complete` or `CompleteUnlessOpen` preferred, `CompleteUntilFirstUserAuthentication` the floor | Must | At-rest protection (T-16) | Automated attribute audit walks the container and asserts the class of every file |
| SEC-33 | Destination credentials stored at `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable` false, by default | Must | Enables background export while blocking backup/device migration of secrets (T-17) [18][19][20] | Keychain attribute assertion test for every credential the app writes |
| SEC-34 | iCloud Keychain sync only as an explicit per-destination opt-in with a plain-language blast-radius warning; never enabled by default or by migration | Must | Both sides argued in §4; `ThisDeviceOnly` and sync are mutually exclusive [20] | Default state is non-synchronizable; opt-in flow presents the warning; asserted by test |
| SEC-35 | All off-device telemetry off by default; no bundled collector endpoint | Must | V-2 | Fresh install emits zero traffic to non-user-configured hosts under packet capture |
| SEC-36 | **No first-party telemetry, analytics or crash-collection endpoint operated by the project** | **Won't** | V-1; avoids GDPR controllership of Art 9 data, MHMDA exposure, HBNR liability | No project-controlled hostname in any shipped default; build-time string/default check |
| SEC-37 | Telemetry attribute keys governed by a CODEOWNERS-protected static **allow-list**; build fails on any key not on it | Must | V-3; makes the whole section enforceable and every change reviewable | CI test enumerates emittable keys and diffs against the allow-list |
| SEC-38 | No verbatim error/exception objects, HTTP bodies, or decoder messages in any telemetry or log; errors mapped to a closed enum first | Must | V-4; the most common real leak path (T-18) | **Canary test:** serialisation failure over a payload containing a unique canary produces telemetry that does not contain the canary |
| SEC-39 | Verbose payload diagnostics only via a user-armed session, auto-expiring ≤60 min, non-backed-up, deleted at expiry | Must | V-7 | Session expires and storage is empty afterwards; asserted by test |
| SEC-40 | No remote configuration of telemetry, sampling, log level, or feature flags | Must | V-8; source must tell the truth about behaviour | No runtime config fetch in the shipped binary; network capture confirms |
| SEC-41 | No third-party crash-reporting, analytics or session-replay SDK | Must | V-5 | Dependency allow-list check (SEC-49) names the prohibited set |
| SEC-42 | On-device logs subject to the same allow-list as off-device telemetry | Must | V-6; local logs reach backups, Files and sysdiagnose (T-19) | Canary test applied to log sinks |
| SEC-43 | Health values not representable in telemetry-bound types; no regex-scrubber approach | Must | V-9; sink-side filtering fails silently on new fields | Type-level review; attempting to attach a sample value fails to compile |
| SEC-44 | Health data and credentials never placed on the general pasteboard without explicit user action, and then local-only with an expiry ≤60s | Must | Clipboard leakage to other apps and Universal Clipboard (T-20) | Test asserts pasteboard item options; no automatic copy anywhere in the app |
| SEC-45 | Share-sheet export shows a one-time warning that data leaves the app's protection domain | Must | Informed consent (T-21) | UI test |
| SEC-46 | Scheduled/unattended exports never use the share sheet or any user-interactive OS surface | Must | Prevents silent hand-off to arbitrary apps (T-21) | Code path review; no share-sheet invocation reachable from the scheduler |
| SEC-47 | CODEOWNERS security review on all egress-critical paths (network I/O, Keychain, Data Protection, ATS config, telemetry allow-list, destination config) | Must | Malicious/careless contributor (T-22) | CODEOWNERS file present and enforced by branch protection |
| SEC-48 | `main` protected: two approvals, no self-merge, no force-push, signed commits, required checks | Must | T-22 | Repository settings audit, recorded per release |
| SEC-49 | Dependency allow-list; new runtime dependency requires justification, transitive-tree review and two approvals | Must | Supply chain (T-23) | CI fails on any resolved dependency absent from the allow-list |
| SEC-50 | Exact version pinning; `Package.resolved` committed and verified unchanged in CI; no branch/range dependencies in release manifests; binary targets require verified checksums | Must | T-23 | CI diff check on `Package.resolved` |
| SEC-51 | Prohibited dependency characteristics enumerated (bundled telemetry, build-time network, unchecksummed blobs, non-OSI licence, no security contact) | Must | T-23 | Documented policy + review checklist |
| SEC-52 | Automated dependency vulnerability scanning per PR and weekly, with a named triage owner | Should | T-23 | Scan results attached to each release |
| SEC-53 | Local notification to the user whenever a new destination is added or an existing one is re-pointed | Must | Coercive insider (T-24) | Test asserts notification fires on destination creation |
| SEC-54 | Destinations, credentials-in-use and the egress ledger can never be hidden, disguised or made inaccessible from the UI; no "stealth" or "hidden" mode, ever | Must | T-24; prevents the app being weaponised as stalkerware | Feature review gate; explicit prohibition recorded in the PRD |
| SEC-55 | macOS build distributed outside the App Store: Developer ID-signed, hardened runtime, notarised, stapled, with published SHA-256 and provenance | Must | Verifiability is attainable on macOS (T-25) | `codesign --verify --deep --strict` and `spctl -a -vv` pass on the published artifact; published hash matches |
| SEC-56 | All CI actions pinned to full commit SHAs; minimal token permissions; no `pull_request_target` with secrets; no self-hosted release runners | Must | Compromised action (T-26) | Workflow audit in CI |
| SEC-57 | Hardware-backed 2FA for maintainers; two maintainers required for a release | Must | T-25 | Organisation settings audit |
| SEC-58 | Automated "egress diff" label and mandatory security review on any PR changing the set of reachable hosts, ports or protocols | Should | Stops T-22 hiding in a large diff | CI label present on a test PR that adds a network call |
| SEC-59 | Signed build provenance attestation binding each release artifact to its source commit and CI workflow | Must | The strongest honest guarantee available on iOS [23][24][25] | Attestation verifies against the published commit for every release |
| SEC-60 | App Privacy nutrition label and `PrivacyInfo.xcprivacy` derived from a reviewed, enumerated **egress inventory**; re-verified every release | Must | App Review requirement since May 2024 [2]; inconsistency risks rejection (T-29) | Inventory document updated and diffed per release; Xcode privacy report matches |
| SEC-61 | No write-back to HealthKit in v1 | Must | Avoids false-data risk and 5.1.3(ii) integrity prohibition [1] (T-31) | No HealthKit write authorisation requested |
| SEC-62 | Bounded queue: delete on successful delivery; hard TTL (proposed 7 days); hard size cap; on expiry delete and alert | Must | Limits A4 exposure window; prevents unbounded on-device accumulation (T-32) | Test: undeliverable payload is gone after TTL and the user is alerted |
| SEC-63 | No feature interprets, diagnoses, screens, alerts on clinical thresholds, or recommends clinical action | Must | Avoids SaMD status under MDR/FDA (T-33) | Feature review gate at every stage |
| SEC-64 | Credential non-portability (consequence of SEC-33) disclosed in the UI **before** the user enters a credential | Must | Prevents a migration surprise that drives users to weaker practices | UI test asserts the disclosure precedes the credential field |
| SEC-65 | Credential *reveal* in the UI gated by biometric/passcode (`.userPresence`); export path never biometric-gated | Must | Physical access (T-15) without breaking unattended export | Reveal prompts for biometrics; scheduled export succeeds with no prompt |
| SEC-66 | Secure Enclave-backed P-256 key wraps the symmetric key protecting credentials and the queue | Should | Hardware device-binding; stolen container useless off-device | Container copied to another device cannot be decrypted |
| SEC-67 | Offer SE-generated client key + exportable CSR for mutual-TLS destinations | Should | Non-exfiltratable client credential for self-hosters | CSR verifies; private key is non-exportable |
| SEC-68 | No claim of Secure Enclave protection for user-supplied PKCS#12 identities | Must | External private keys cannot be imported into the SE; overclaiming is a false security statement | Documentation review |
| SEC-69 | In-app "delete all credentials, queued data, logs, ledger and history", idempotent and verifiable; macOS uninstall docs cover manual Keychain removal | Must | Credentials outlive app deletion on macOS; iOS behaviour must not be relied on | Post-action keychain enumeration by access group returns zero items; container contains no payloads |
| SEC-70 | Revoking HealthKit authorisation for a type purges that type's queued payloads within 60 seconds | Must | Consent withdrawal must be effective, not just prospective | Timed test |
| SEC-71 | Optional manual SPKI pinning per destination for advanced users | Could | Serves users with a strong threat model | Pinned destination rejects a different certificate |
| SEC-73 | Documented prohibition on providing the app to or on behalf of a HIPAA covered entity without fresh legal review | Must | The only route by which HIPAA could attach [3][4][5] | Recorded in the PRD and in `SECURITY.md` governance notes |
| SEC-74 | In-app **security advisory channel** capable of delivering a breach or vulnerability notice to users | Must | FTC HBNR notification capability [6][7][8]; we hold no user list by design | A test advisory is delivered to a device in the release rehearsal |
| SEC-75 | Privacy policy states plainly that the project collects, sells and shares no personal information, and enumerates what leaves the device and to where the user directed it | Must | App Review requirement [1]; CCPA/CPRA good practice; truthfulness | Policy reviewed against the SEC-60 egress inventory each release |
| SEC-76 | No feature may geofence or trigger behaviour based on proximity to a health-care facility | Must | Per se WA MHMDA violation with a private right of action attached [27][28] | Feature review gate; no such API usage |
| SEC-77 | HealthKit authorisation requested incrementally, per type, at the point of configuring an export that needs it | Must | Least privilege; over-broad HealthKit requests are a common App Review rejection [1] | Fresh install requests zero types until a destination is configured |
| SEC-78 | No price, paid tier, or donation-gated release artifact without a recorded CRA re-analysis; free binaries and security updates available to everyone regardless of donation | Must | Determines manufacturer vs steward vs out-of-scope status [9][10][11] | Release checklist gate; distribution audit |
| SEC-79 | Publish a documented cybersecurity policy satisfying CRA Art 24, regardless of which CRA row we occupy | Must | Cheap; required if we are a steward; good practice otherwise [10][11] | Policy published in-repo and referenced from `SECURITY.md` |
| SEC-80 | Generate and publish an SBOM per release | Should | Required for manufacturers from Dec 2027 [12][13]; useful now | SBOM artifact attached to every release |
| SEC-81 | No regulatory-compliance claim in marketing or store listing that we cannot substantiate with a citation | Must | Unfalsifiable privacy marketing is what this project exists to improve on | Claims reviewed against the Sources list each release |
| SEC-82 | Publish build environment (Xcode/Swift versions, toolchain hashes) and a documented verification procedure with stated limitations | Should | Maximises what verification is possible [23][24][25] | Documentation present; a third party can follow it |
| SEC-83 | **Prohibit** any claim of "reproducible", "verifiable" or "auditable binaries" for the iOS App Store build | Must | Not achievable on iOS; the claim would be false [23][24][25] | README, store listing and marketing copy reviewed per release |
| SEC-84 | `SECURITY.md` with supported versions, private reporting channel, PGP/Signal contact, 5-business-day ack SLA, 90-day disclosure default, scope, safe harbour, and an explicit no-bounty statement | Must | Coordinated disclosure is a baseline OSS obligation and a CRA Art 24 element [11] | File present and complete; a test report receives acknowledgement within SLA |
| SEC-85 | CVD process aligned to ISO/IEC 29147 and 30111 with named responders and a deputy | Must | Serves as the Art 24 policy (SEC-79) | Process documented; a tabletop exercise completed before v1 launch |
| SEC-86 | CVE issuance via GitHub CNA plus published advisories plus in-app delivery (SEC-74) | Must | Users cannot act on a fix they never hear about | Advisory published and delivered for any confirmed vulnerability |
| SEC-87 | If CRA manufacturer status applies, pre-establish and rehearse the ENISA/CSIRT 24h/72h/14d reporting path | Should | Deadlines are missed by teams discovering the process mid-incident [11][12] | Tabletop exercise recorded |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A user silently exports their health record to the wrong host for months and nobody, including them, ever finds out | **High** | Catastrophic and irreversible | SEC-09 canary handshake, SEC-10 identity display, SEC-11 egress ledger, SEC-12 dry-run preview, SEC-13 pin-on-first-use. Treat these five as a single non-divisible feature; shipping four of five leaves the hole open |
| Observability requirements erode in Stage 2/3 and health data ends up in span attributes | **High** — this is the default outcome, not a tail case | Severe; converts a privacy tool into a leak and changes our regulatory status | SEC-37 CI-enforced allow-list, SEC-38 canary test, SEC-43 type-level impossibility. The allow-list must be CODEOWNERS-protected or it will be edited without review |
| App Review rejects us under 5.1.3(ii) over an iCloud destination or a backed-up container | Medium | Blocks distribution; late-stage rework | SEC-30, SEC-31; resolve the user-initiated-iCloud-Drive question with App Review **before** implementation (Q3) |
| The listening server is reinstated for parity with the reference product | Medium — competitive pressure is real | Severe: authorisation bypass for every co-resident app, plus probable 5.1.3(i) violation | SEC-01 as a recorded Won't with the T-11 rationale in the PRD, so reinstatement requires overturning a written finding rather than filling a gap |
| Project takes donations or adds a paid tier and unknowingly becomes a CRA manufacturer | Medium | Full Annex I regime, CE marking, conformity assessment — infeasible for this project | SEC-78 gate on the release checklist; make the CRA row an explicit, recorded PM decision |
| A single maintainer becomes a single point of compromise for signing and release | Medium | Total, for every user | SEC-57 two-maintainer release, SEC-59 provenance, SEC-56 pinned actions |
| Queued health data accumulates unbounded on device because a destination has been dead for months | Medium | Prolonged A4 exposure; the "data stays on device" claim quietly becomes a liability | SEC-62 TTL and size cap with user alerting |
| The app is weaponised as stalkerware by a coercive insider | Medium | Severe physical-safety harm to a real person | SEC-53 new-destination notification, SEC-54 no-hiding prohibition, SEC-11 auditable ledger, SEC-29 app-level gate |
| Metadata leakage (SNI, timing, volume) reveals health-app use and activity patterns even under correct TLS | High | Moderate, and **not fully mitigable** | SEC-23 padding/jitter as a Should; honest documentation. I am not claiming to solve this and we must not imply that we do |
| Security requirements are triaged out under Stage 3 schedule pressure | **High** | Varies; the loss is usually invisible until an incident | Every requirement here has a stated verification method so that removal is a visible decision. If forced to keep only three tests: SEC-38 canary, SEC-30 backup inspection, SEC-15 connect-time address re-check |

---

## Hard constraints that limit the product

Stated loudly, per the rules of engagement. These remove or reshape desirable functionality.

1. **No listening server on iOS. This removes a headline reference-product feature.** T-11 is not
   mitigable — there is no way to attribute a loopback peer to a specific app, so a localhost
   listener is an unauthenticated HealthKit read for every app on the device.
2. **No iCloud/iCloud Drive/CloudKit destination for health data, and no health data in a
   backed-up container.** App Review 5.1.3(ii) [1]. This removes a reference-product destination
   and constrains cross-device sync architecture at Stage 2.
3. **Destination credentials do not migrate to a new device by default.** A consequence of
   `ThisDeviceOnly` (SEC-33). Device migration will require credential re-entry, and the UX must
   own that rather than hide it.
4. **No third-party crash reporting or analytics of any kind.** We will therefore have
   *materially worse* field diagnostics than a typical app, and will depend on users voluntarily
   reporting issues with their own local diagnostic sessions. This is a real product cost and I
   accept it deliberately.
5. **The observability differentiator ships in a reduced form.** No health types, no destination
   hostnames, no verbatim errors in telemetry. The user's own collector may receive structure,
   timing and outcomes — enough to diagnose failure, and no more.
6. **iOS App Store binaries cannot be verified against source.** The "genuinely open source,
   auditable by the people whose data it moves" differentiator is true of the *source* and of
   *build provenance*, not of the shipped iOS binary [23][24][25]. Marketing must say so.
7. **No interpretation, scoring, or clinical alerting features**, at any point, without a
   deliberate medical-device regulatory decision (SEC-63).
8. **Monetisation is a security-and-compliance decision, not just a business one.** Charging a
   price, or gating binaries/updates behind donations, converts us into a CRA manufacturer with
   obligations this project cannot realistically carry [9][11][12].
9. **We cannot notify users individually of a breach**, because we deliberately hold no user
   list. In-app advisories (SEC-74) are the best available substitute and must be built in v1.
10. **Traffic-analysis resistance is not offered.** An observer can tell that health data is
    being exported and roughly when, even when they cannot read it.

### What I will not sign off on, named

1. Any listening server on iOS, at any point, authenticated or not (§3, T-11).
2. Any first-party telemetry, analytics or crash-collection endpoint operated by the project
   (SEC-36).
3. Any claim that iOS App Store builds are reproducible, verifiable or auditable (SEC-83).
4. `NSAllowsArbitraryLoads` in a shipped build, for any reason (SEC-19).
5. App-managed storage of health data in iCloud/CloudKit, or health payloads in a backed-up
   container (SEC-30, SEC-31).
6. Any bundled third-party crash/analytics SDK (SEC-41).
7. Shipping OpenTelemetry without the CI-enforced attribute allow-list and the canary test
   (SEC-37, SEC-38).
8. iCloud Keychain credential sync as a default (SEC-34).
9. Any hidden, stealth or disguised operating mode (SEC-54).
10. Any interpretation or clinical-alerting feature (SEC-63).
11. Charging a price or gating releases behind donations without a recorded CRA re-analysis
    (SEC-78).
12. Blanket up-front HealthKit authorisation for all types (SEC-77).

---

## Open questions for the PM

- **Q1 — Legal entity and monetisation.** Who publishes this: a named individual, or a company or
  foundation? Free forever, donations, or a paid tier? This single answer decides whether we are
  outside the CRA entirely, an OSS steward under Art 24, or a full manufacturer [9][10][11][12].
  I cannot finalise SEC-78/79/80/87 without it, and manufacturer reporting duties begin on
  **11 September 2026**.
- **Q2 — Is the listening server negotiable?** I have recorded it as a Won't for iOS with the
  T-11 rationale. If the PM intends parity with the reference product regardless, I need that as
  an explicit written override with a named owner, because it is an authorisation bypass and a
  probable 5.1.3(i) violation, not a risk trade.
- **Q3 — iCloud Drive destination.** Do we (a) drop it, (b) ship user-initiated document-picker
  export only and accept App Review risk, or (c) pre-clear the question with App Review before
  Stage 2 implementation? I recommend (c), then (a) if the answer is unfavourable. I cannot
  resolve the 5.1.3(ii) ambiguity from published guidance.
- **Q4 — Are we willing to be materially blind in the field?** SEC-36 and SEC-41 mean no crash
  reports, no adoption data, no aggregate error rates. That is my recommendation and I am
  confident in it, but it is a product decision with real support consequences, and the PM should
  own it rather than inherit it.
- **Q5 — Queue TTL.** I propose 7 days for undeliverable payloads, then delete-and-alert. Longer
  favours the intermittently-connected self-hoster; shorter reduces A4 exposure. PM to set.
- **Q6 — watchOS scope.** Health data on the Watch has a different Data Protection and background
  execution story that I have not threat-modelled here. Is watchOS in v1 scope as a full export
  origin, or companion-only? If full, I need a Stage 1 addendum.
- **Q7 — Legal review budget.** Two questions need a lawyer, not an engineer: whether an
  unmonetised OSS project is a "vendor of personal health records" under the amended FTC HBNR
  [6][7][8], and the current status of New York's Health Information Privacy Act, revived in the
  2026 session, which I could not verify [26]. Is there budget for a short opinion? If not, I
  recommend we behave as if in scope for HBNR, since SEC-74 is cheap.
- **Q8 — Who owns the security-maintainer role?** SEC-47, SEC-84 and SEC-85 all assume a named
  person with a named deputy and an acknowledgement SLA. An unowned `SECURITY.md` is worse than
  none, because it promises a response nobody has agreed to give.

---

## Sources

All URLs retrieved 2 September 2026.

1. Apple, *App Store Review Guidelines* (5.1.1, 5.1.2(vi), 5.1.3, 2.5.1) — https://developer.apple.com/app-store/review/guidelines/
2. Apple, *Third-party SDK requirements* (privacy manifests, signatures, required-reason APIs) — https://developer.apple.com/support/third-party-SDK-requirements
3. HHS OCR, *The access right, health apps, & APIs* — https://www.hhs.gov/hipaa/for-professionals/privacy/guidance/access-right-health-apps-apis/index.html
4. HHS OCR, *Business Associates* — https://www.hhs.gov/hipaa/for-professionals/privacy/guidance/business-associates/index.html
5. Summary of HHS OCR guidance for health app developers (consumer-populated apps are not business associates) — https://compliancy-group.com/ocr-guidance-health-app-developers/
6. FTC, *Health Breach Notification Rule*, final rule, 89 FR 47028 (30 May 2024; effective 29 July 2024) — https://www.govinfo.gov/content/pkg/FR-2024-05-30/pdf/2024-10855.pdf
7. Venable LLP, *FTC Announces Final Changes to Health Breach Notification Rule* — https://www.venable.com/insights/publications/2024/07/final-changes-to-health-breach-notification
8. FTC, *Mobile Health App Interactive Tool* — https://www.ftc.gov/business-guidance/resources/mobile-health-apps-interactive-tool
9. European Commission, *Guidance on the Cyber Resilience Act*, C(2026) 5252 final, 27 July 2026 (§§22–24, 41, 50–53, 60–62, 69–78; Examples 3, 20–22) — https://kunnus.tech/downloads/eu-cra-commission-guidance-c2026-5252.pdf
10. European Commission, *Cyber Resilience Act — Open source* — https://digital-strategy.ec.europa.eu/en/policies/cra-open-source
11. OpenSSF / Linux Foundation, *CRA Stewards Playbook* (Art 14 and Art 24 obligations) — https://policy.openssf.org/CRA/stewards-playbook.html
12. Mend.io, *EU Cyber Resilience Act: 2026 Compliance Guide* (timeline: 11 Sep 2026 reporting; 11 Dec 2027 full) — https://www.mend.io/blog/eu-cyber-resilience-act-compliance-guide/
13. OpenSSF / Linux Foundation, *CRA Stewards One Pager* — https://policy.openssf.org/CRA/stewards-one-pager.html
14. Apple, *Preventing Insecure Network Connections* (ATS exceptions requiring justification; `NSAllowsLocalNetworking` does not) — https://developer.apple.com/documentation/security/preventing-insecure-network-connections
15. Apple Developer, *How to use multicast networking in your app* (Bonjour, local network privacy) — https://developer.apple.com/news/?id=0oi77447
16. Apple, *NSLocalNetworkUsageDescription* — https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription
17. EDPB, *Guidelines 3/2019 on processing of personal data through video devices*, v2.0 (household exemption must be narrowly construed) — https://www.edpb.europa.eu/sites/default/files/files/file1/edpb_guidelines_201903_video_devices.pdf
18. Apple, *Keychain data protection* (accessibility classes; `ThisDeviceOnly` items do not sync and are not backed up) — https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web
19. Apple, *Restricting keychain item accessibility* — https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
20. Apple, *Accessing Keychain Items with Face ID or Touch ID*; and `kSecAttrSynchronizable` + `ThisDeviceOnly` → `errSecParam` — https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id
21. Apple, *Protecting access to user's health data* / Health privacy white paper (Health data end-to-end encrypted; included in iCloud Backup; local backups only if encrypted) — https://support.apple.com/guide/security-pdf/protecting-access-to-users-health-data-sec88be9900f/web
22. GDPR Recital 18 and Art 29 Working Party statement on personal and household activities (the exemption does not extend to those providing the means) — https://ec.europa.eu/justice/article-29/documentation/other-document/files/2013/20130227_statement_dp_annex2_en.pdf
23. Immuni iOS, *Reproducible builds* issue #217 (FairPlay encryption; normalising `LC_UUID`, `LC_CODE_SIGNATURE`, `LC_ENCRYPTION_INFO_64`, `__LINKEDIT`) — https://github.com/immuni-app/immuni-app-ios/issues/217
24. Signal-iOS, *Reproducible builds* issue #641 (embedded signatures and FairPlay make bit-for-bit reproduction impossible) — https://github.com/signalapp/Signal-iOS/issues/641
25. OWASP MASTG, *iOS Platform Overview* (FairPlay encryption of App Store binaries; App Attest) — https://mas.owasp.org/MASTG/0x06a-Platform-Overview/
26. Nixon Peabody, *When HIPAA compliance isn't enough: the growing reach of state health privacy laws* (31 Aug 2026; NY HIPA revived in the 2026 session) — https://www.nixonpeabody.com/insights/articles/2026/08/31/when-hipaa-compliance-isnt-enough-the-growing-reach-of-state-health-privacy-laws
27. Washington State Attorney General, *Protecting Washingtonians' Personal Health Data and Privacy* (MHMDA; per se CPA violation; geofencing) — https://www.atg.wa.gov/protecting-washingtonians-personal-health-data-and-privacy
28. WilmerHale, *First Lawsuit Filed Under Washington's My Health My Data Act* (private right of action in practice) — https://www.wilmerhale.com/en/insights/blogs/wilmerhale-privacy-and-cybersecurity-law/20250220-first-lawsuit-filed-under-washingtons-my-health-my-data-act
29. Brownstein, *Nevada's New Consumer Health Data Law — Explained* (SB 370; no private right of action) — https://www.bhfs.com/insight/nevada-s-new-consumer-health-data-law-explained/
30. European Commission Data Act FAQs, summarised (related service requires two-directional data exchange; on-device storage with no manufacturer access means "only a user and no data holder") — https://www.lexology.com/library/detail.aspx?g=3b609a22-573d-41cb-867c-83184473dbb7
31. Setterwalls, *Five steps to ensure Data Act compliance for IoT products and services within the MedTech sector* (an app that merely displays data is not a related service) — https://setterwalls.se/en/article/five-steps-to-ensure-data-act-compliance-for-iot-products-and-services-within-the-medtech-sector/
32. European Commission, *Data Act explained* — https://digital-strategy.ec.europa.eu/en/factpages/data-act-explained
33. Regulation (EU) 2023/2854 (Data Act), full text — https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=OJ%3AL_202302854

**Explicitly not verified**, flagged per the rules of engagement: whether `NSAllowsLocalNetworking`
covers RFC 1918 IP literals as well as unqualified and `.local` names (§5 Part 2, item 2 — must
be confirmed empirically with `nscurl` in Stage 2); the current legislative status of New York's
Health Information Privacy Act (§6); the exact application date of EU Data Act Chapter II
(immaterial, as we are out of scope on substance); and whether App Review treats a user-initiated
document-picker export to a user-chosen iCloud Drive location as the app "storing personal health
information in iCloud" under 5.1.3(ii) (Q3 — I recommend a pre-submission enquiry rather than
shipping on my reading).
