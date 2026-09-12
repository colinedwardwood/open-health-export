# Security Design — Stage 2

> **Stage 2 artifact.** Control designs, trust boundaries, enforcement points and verification
> methods. No implementation, no Swift. Every control names the thing that makes it hold —
> a type, a build gate, a state machine, or an honest admission that nothing does.
>
> **Author:** Senior Security Engineer
> **Date:** 3 September 2026
> **Inputs:** `docs/01-prd/PRD.md` v1.0 (approved), `docs/01-prd/contributions/04-security-engineer.md`,
> `docs/01-prd/reviews/01-adversarial-review.md` (AR-F-01, AR-F-04 accepted),
> `docs/adr/0001-licence-agpl-3.0-with-app-store-permission.md`
> **Owns:** R-30…R-44, R-51, the security properties of R-31; C-05…C-12.
> **Regulatory and Apple-policy claims cited and current as of 3 September 2026.**

---

## Executive summary

Stage 1 said the highest-value security property in this product is not confidentiality of the
transport but the user's ability to know, verify and audit where their data went. Stage 2's job
is to turn that sentence into structures that cannot be quietly removed. The organising
principle throughout is the same one: **make the secure path the only representable path, so
that erosion is a compile error or a red build rather than a judgement call in review.** RK-5
says erosion in Stage 2/3 is the default outcome and I am the person who said so; the designs
below are shaped by that belief more than by any threat.

Six things a reader should take away.

**1. R-31's indivisibility is a type, not a promise.** The export path accepts only a
`VerifiedDestination`, and the only way to construct one is the terminal transition of a state
machine that has already run the canary handshake, displayed certificate identity, shown the
dry-run preview and recorded a first-use pin. "Ship four of the five" stops being a scope
decision available to a future implementer.

**2. The egress ledger is tamper-evident, not immutable, and I will not let us claim
otherwise.** It is a hash chain sealed by a Secure Enclave key, with the delete-all action
writing a genesis marker recording how many entries were destroyed and when. A coercer can
still wipe it. They cannot make the wipe invisible. That is the real guarantee and R-30's
acceptance criterion needs rewording to match it.

**3. The advisory channel's defence against becoming telemetry is a golden-request test.**
Not a policy, not a code comment: a committed fixture containing the exact bytes of the
outbound request, compared on every commit. Adding a query parameter, an `ETag`, a cookie or a
finer-grained `User-Agent` fails the build and forces a contributor to edit a CODEOWNERS-guarded
expectation file. The endpoint is a static object with no server-side logic: the client filters,
the server never selects. A second property matters as much and nobody has asked for it —
advisory content is **display-only** and can never alter app behaviour, so the endpoint cannot
become a kill switch.

**4. The Mac companion's "outbound push, not listening server" framing is half true, and the
half that is false is the important half.** It correctly preserves the reason we banned the iOS
listener — on iOS there is still no socket, so a co-resident app still cannot launder HealthKit
consent (T-11). It does not mean the product has no listening server. It has one; it is on the
Mac; and SEC-02's seven controls now bind. Worse, the companion introduces a hazard nobody has
flagged: it writes a decrypted health archive into a user-chosen folder, unattended and
repeatedly, and if that folder is iCloud-synced then our app — not the user in Apple's own
picker — is storing personal health information in iCloud. See §*LAN surfaces*.

**5. Two owned requirements are unsatisfiable as written and one acceptance criterion will
fail on first contact with a packet capture.** R-44's 60-second revocation purge cannot start
at the revocation event, because Apple deliberately makes read-authorisation revocation
undetectable. R-41's "can never be hidden" is defeated by iOS 18's own Hide-and-Require-Face-ID
feature, operated by exactly our threat actor. And R-32's "network capture shows zero traffic"
will show OCSP, CT and DNS traffic the OS initiates on our behalf. All three need restating,
and §*Requirements I cannot secure as written* proposes the wording.

**6. The MQTT dependency review has a conclusion that is not "which library".** Every
third-party MQTT stack brings its own TLS implementation, which means our R-32 allowlist
chokepoint and our R-31 pin-on-first-use logic are **not on that code path**. Adopting one
either fragments the single enforcement point that the whole egress story rests on, or forces us
to reimplement pinning inside someone else's callbacks. I recommend a first-party publish-only
MQTT 3.1.1 client over `Network.framework`, reusing the transport we are already building, and I
put the burden of proof on adopting a library rather than on avoiding one.

On regulation, D-03's legal entity moves us from "out of scope entirely" to a genuine
steward-versus-manufacturer question, and D-08's sponsorship sharpens it. My engineering
recommendation removes most of the urgency: **build to CRA Article 24 regardless of the
answer**, because the marginal cost over SEC-79/84/85 is close to zero. What the R-112 opinion
must actually resolve is narrower and sharper than "are we a steward", and includes one question
nobody has asked: the advisory endpoint's access logs are the first personal data this project
has ever processed, they are controlled by a legal entity, and there is a real argument they are
Article 9 data.

---

## Updated threat model

Delta from Stage 1's 33 threats. Assets, boundaries and actors are unchanged except where
noted; the Stage 1 assumption "we operate no server-side infrastructure of any kind" is now
**false** — R-38's advisory endpoint is server-side infrastructure, even if it is a static file.
That single change is why §*Regulatory posture* has to be re-run.

### Changed trust boundaries

| ID | Change |
|---|---|
| TB4 | Now has three protocol families behind it (HTTPS, MQTT, companion), not one. The pinning and allowlist logic must be **one implementation shared by all three**, or the boundary has three different strengths |
| TB5 | Reinstated. Stage 1 closed the LAN boundary by refusing a listener. D-14 reopens it: the iPhone makes an outbound LAN connection, and the Mac operates a listening server |
| TB8 | Was "default closed" with nothing behind it. Now has a single inbound member (R-38). The boundary is no longer closed, it is *narrow*, which is a weaker and more maintainable-away property |
| **TB11 (new)** | **Project-controlled origin → user device.** The advisory endpoint. First infrastructure we operate. Enforced by feed signing, a pinned verification key, and the golden-request test |
| **TB12 (new)** | **Mac companion process → macOS filesystem, Time Machine, Spotlight, iCloud Drive.** The decrypted archive leaves HealthKit's protection domain and lands somewhere with a different threat model |

### New threats

| ID | Threat | Actor | Impact | Likelihood | Control |
|---|---|---|---|---|---|
| **T-34** | Hostile or later-compromised MQTT broker reads everything published to it | Broker operator | Total disclosure of what is published | Medium | Same as T-02/T-03: per-destination minimisation (SEC-16), pin-on-first-use, canary handshake. **Publish-only client** means the broker gets no inbound command channel |
| **T-35** | Retained MQTT messages leave a health payload on the broker indefinitely, replayed to every future subscriber including ones added later | Broker / user error | Persistent disclosure the user did not intend and cannot see | **Medium-high** — retain is on by default in much MQTT tooling | Retain **off by default for data topics**, permitted only for Home Assistant discovery/config topics, which carry no sample values. Retain state shown per destination and recorded in the ledger |
| **T-36** | A third-party MQTT library brings its own TLS stack, bypassing our allowlist chokepoint (R-32) and our pin-on-first-use logic (R-31) | Us (architecture) | Silent divergence: one destination class with weaker verification than the UI claims | **High if a library is adopted without this being designed for** | First-party publish-only client (recommended), or a written mapping of every one of R-31/R-32/R-35's checks onto the library's callback surface, tested per-check |
| **T-37** | Vendored C (BoringSSL via `swift-nio-ssl`) executes in the process holding A1 and A2 | Upstream | Memory-safety surface adjacent to the crown jewels | Low probability, high impact | Prefer the platform TLS stack (`Network.framework`), which is already in the process and is Apple's problem to patch |
| **T-38** | LAN attacker MITMs the iPhone↔Mac pairing exchange and becomes the "companion" | Network attacker | Total disclosure, ongoing, appearing legitimate | Medium at pairing time, near-zero afterwards | Short-authentication-string comparison on both screens before pinning; no "continue anyway" affordance |
| **T-39** | The companion writes the health archive into an iCloud-synced folder (Desktop/Documents sync, iCloud Drive) | Us + user | PHI in iCloud: C-05 / Guideline 5.1.3(ii) exposure, plus third-party cloud disclosure | **Medium-high** — Desktop & Documents sync is on by default for many users | Companion refuses iCloud-synced destinations by default; explicit override with a named-risk confirmation; recorded in the ledger. **Pre-submission enquiry recommended** |
| **T-40** | A co-resident macOS process running as the same user extracts the companion's private key from the login keychain | Co-resident process | Companion impersonation → the iPhone pushes to an attacker | Low–Medium (Intel Macs), Low (Apple silicon) | Secure Enclave-generated, non-exportable key where available; keychain ACL bound to the signed app; documented residual on Intel |
| **T-41** | Bonjour advertisement discloses "a health-data receiver runs here" to everyone on the network | Network attacker | Targeting, detectability | High if advertised continuously | Advertise a generic service type with an opaque TXT payload, **only during a user-opened, time-boxed pairing window**; manual address entry as the primary path |
| **T-42** | The advisory channel accretes into telemetry: a query parameter, a conditional-request `ETag`, a build number in `User-Agent`, per-client server-side selection | Contributor (well-intentioned) | Collapses the wedge; makes us a controller of health-adjacent data | **High over a multi-year project** — this is the RK-5 pattern applied to a new surface | Golden-request byte fixture in CI; static-only origin; client filters, server never selects; CODEOWNERS |
| **T-43** | The advisory channel accretes into remote configuration or a kill switch | Contributor / compromised key | The shipped source stops telling the truth about behaviour; a single origin can disable everyone's exports | Medium | Advisory model carries no behavioural fields; a test asserts the parsed model is consumed only by presentation code; export never depends on advisory reachability |
| **T-44** | Network attacker suppresses or rolls back the advisory feed, freezing a device at a pre-vulnerability view | Network attacker | Users never learn of a vulnerability | Medium | Monotonic sequence number, `expires_at`, and a signed heartbeat republished on a fixed cadence; client surfaces "advisories stale" after 30 days |
| **T-45** | Advisory signing key compromise → forged advisory directing users to a malicious "fix" | Attacker on TB9 | Broad, high-credibility phishing of exactly the users who trust us | Low, high impact | Offline key; two pinned keys with rotation only by app update; advisories are display-only with full URLs shown, never auto-actioned |
| **T-46** | Advisory endpoint access logs (IP + timestamp + version) held by a **legal entity** constitute processing of personal data, plausibly special-category by inference | Us (regulatory) | GDPR controllership of Art 9 data — the exact outcome R-37 exists to prevent | Medium | Static host with access logging disabled or minimised; documented in the privacy policy; R-112 question 6 |
| **T-47** | The legal entity distributing free FOSS via a commercial app store is held to have placed it on the market → CRA **manufacturer** | Us (regulatory) | Annex I, CE marking, conformity assessment — infeasible | Low–Medium, and unresolved | R-110 keeps donations ungated; R-112 questions 1–3; build to Art 24 regardless |
| **T-48** | Named sponsorship (D-08) creates a commercial-activity nexus that changes the classification | Us (regulatory) | Same as T-47 | Low | Sponsors receive acknowledgement only — no roadmap influence, no priority support, no gated artifacts (R-110). R-112 question 4 |
| **T-49** | **A coercer with the passcode hides the app using iOS 18's own Hide-and-Require-Face-ID feature.** The app vanishes from the Home Screen into an authentication-gated folder, and its notification previews are suppressed | Coercive insider | **Defeats R-41 entirely and R-40 substantially** | **Medium, and it is trivially easy** | Nothing we ship prevents it. Documented in the in-app Personal Safety page and the README; R-41 restated as a property of our binary. See §*Anti-coercion* |
| **T-50** | An employer's supervised-device MDM installs the app, configures a destination, suppresses notifications via managed settings and prevents removal | Coercive insider (institutional) | Same as T-24, with the victim having no remedy on-device | Low–Medium | Not defensible. Surface a persistent "this device is managed by an organisation" banner where a managed app configuration is detectable; state the limit plainly |
| **T-51** | A coercer uses R-43 delete-all to destroy the ledger evidence of the destination they added | Coercive insider | Loss of the audit record the victim would need | Medium | Delete-all writes a genesis marker into the new ledger: *N entries destroyed at time T*. The wipe is recoverable-as-a-fact even though the entries are not |

### Changed likelihoods and dispositions

| ID | Stage 1 | Stage 2 | Why |
|---|---|---|---|
| T-08 / T-09 | "Not applicable — no listener" | **Applicable on macOS, Medium** | The companion listens. SEC-02's seven controls now bind (mapped in §*LAN surfaces*) |
| T-10 (DNS rebinding) | "Medium if shipped" | **Structurally eliminated** | The companion protocol is not HTTP and requires a client certificate before any application byte. A browser cannot produce one |
| T-11 (localhost laundering) | Disqualifying | **Still fully avoided on iOS** | This is the part of the "outbound push" framing that genuinely survives |
| T-24 (coercive insider) | Medium, severe | **Medium, severe — and less mitigable than Stage 1 assumed** | T-49 was not in the Stage 1 model. Our escalation chain runs through surfaces the OS lets a passcode-holder switch off |
| T-27 (repudiation) | High if unmitigated | **Low** | Hash-chained, SE-sealed ledger with a destruction marker |
| T-28 (we become a controller) | Medium (drift) | **Medium, and now partly realised** | Not through telemetry, but through T-46's access logs. The wedge survives; the "we process nothing" claim needs one sentence of qualification |
| T-32 (unbounded queue) | Medium | **Medium** | D-11 set the cap and eviction policy but **not the TTL**. Stage 1 Q5 is still open and it belongs to me. See §*Open questions* |

---

## Control designs

### R-30 — The append-only egress ledger

**What it is for.** One question, answerable by a non-technical user without developer tools:
*what left my device, when, to where, and did it arrive?* Everything else in this section is
subordinate to that.

**Record structure.** Two entry kinds per transmission, not one:

- an **attempt** entry, committed durably *before* the first byte leaves; and
- an **outcome** entry, referencing the attempt's identifier.

An attempt with no outcome is itself a finding — it means we died mid-flight — and it maps onto
R-21's `unknown_ack` / `abandoned_no_budget` / `cancelled_by_system` taxonomy. A single mutable
row that gets updated in place would be simpler and would destroy the append-only property, so
it is forbidden.

Each entry carries: monotonic sequence number; wall-clock and monotonic timestamps; destination
identifier and the user's own label; the resolved address and its class (public / private /
link-local); transport security state (protocol, negotiated TLS version, leaf SPKI digest, trust
anchor kind — public CA / user-imported CA / pinned self-signed / **none**); pin state (first
use / matched / **changed**); the set of HealthKit type identifiers included; sample count;
byte count; and the outcome enum. Failures, refusals and halted-on-pin-change events are entries
too — a ledger that records only successes is a marketing surface.

**The append-only guarantee.** Three layers, in increasing order of strength and decreasing
order of scope:

1. **No mutation API exists.** The ledger store type exposes `append` and read operations and
   nothing else. There is no update, no delete-entry, no compaction. This is the layer that
   holds against our own future carelessness, which is the likeliest failure.
2. **Hash chain.** Entry *n* commits to `H(sequence ‖ previous_entry_hash ‖ canonical_bytes)`.
   Any edit, reorder or excision of an interior entry is detectable by a linear verification
   pass, which the app runs on launch and reports on in the ledger UI.
3. **Chain-head seal.** The current head hash is signed by a non-exportable Secure Enclave
   P-256 key generated at first run. An attacker who rewrites the file off-device cannot produce
   a valid seal, and one who wipes the container gets a new key — which the UI reports as
   *ledger identity changed*, with the date.

**What this does not give us, stated plainly.** This is tamper-**evident**, not immutable. The
device owner — and therefore the coercer holding the passcode — can destroy the container. What
they cannot do is destroy it *silently*: see R-43 below, and T-51.

**Retention.** No automatic eviction. An entry is on the order of 200 bytes; ten years of hourly
runs is under 20 MB. Eviction would be the mechanism by which an inconvenient history disappears,
so we do not build one. If growth ever becomes a real constraint, the answer is a smaller entry,
not a shorter history.

**Redaction boundary.** The ledger deliberately contains hostnames and HealthKit type
identifiers — the two categories the telemetry allowlist (R-51) forbids, because Stage 1
established that both are health data by inference. There is no contradiction: the ledger is
on-device, user-facing, and **never egress-capable**. Exporting it is a distinct user action
that passes through R-26's full-contents preview, and the ledger is **excluded from the
diagnostic bundle** so that R-26's canary criterion ("no hostnames present") remains satisfiable.
That exclusion is a design constraint on whoever builds the bundle, and it should be an
assertion in their tests, not a note in their head.

**Acceptance criterion, restated.** R-30 currently says "ledger entries exist for every run and
are immutable". Proposed: *"…and are tamper-evident: an out-of-band edit to the ledger store is
detected on next launch and reported to the user; destruction of the ledger is recorded in its
successor."* See §*Requirements I cannot secure as written*.

---

### R-31 — Destination verification as one indivisible feature

Stage 1's risk register says: *treat these five as a single non-divisible feature; shipping four
of five leaves the hole open.* The design problem is that "indivisible" is a wish unless
something enforces it. Here is the something.

**The state machine and the unforgeable token.** A destination occupies exactly one state:

```
draft → previewed → canary_sent → canary_confirmed → pinned → enabled
                                                          ↘ halted (pin change)
```

The health-data export path accepts a **`VerifiedDestination`** value and nothing else. That
type has no public initialiser; the only construction site is the `pinned → enabled`
transition. Consequences that matter more than the diagram:

- Deleting the canary handshake does not "descope a feature"; it removes a transition and the
  terminal state becomes unreachable, so nothing exports at all. The failure is loud and immediate.
- A test-only shortcut is the obvious way to defeat this. Therefore the escape hatch is a
  fault-injection seam under R-83 — **present in test builds only, absent from release builds**,
  with the existing R-83 verification (each seam exercised by a test; asserted absent from
  release) covering it.
- A CI check asserts the export sender's signature accepts only `VerifiedDestination`, so a
  future overload taking a raw destination is a red build.

**Part 1 — Canary handshake.** A benign, non-health payload carrying a randomly generated
verification code, in the destination's real wire format, over the real transport, with the real
credential. The user must **read the code back from the receiving side** and enter it. This is
deliberately stronger than "confirm you received something": reading the code back proves the
user controls the endpoint, which is the exact property T-01 (typo'd hostname) and T-03
(malicious destination) attack.

Per destination class:

| Destination | Read-back channel |
|---|---|
| Local file | The code is written into the folder; the user opens it in Files |
| HTTPS / Home Assistant | The code appears in the receiving system (HA notification, log, or the reference receiver's UI) |
| MQTT | Published to the configured topic; the user reads it in their broker UI or subscriber |
| Mac companion | Displayed on the Mac. The best channel we have, because the second device is genuinely out-of-band |

Where read-back is genuinely impossible (a fire-and-forget HTTP sink with no user-visible
surface, MQTT at QoS 0), the destination cannot reach `enabled` on a confirmed handshake. It can
only reach it via an explicit, ledger-recorded acknowledgement that **delivery to this
destination is unverifiable**, which is R-25's `Sent, unconfirmed` promoted to a property of the
destination rather than of a single run, and which is displayed permanently in the destination
list.

**Part 2 — Certificate identity display.** At the confirmation step, non-truncated and
copyable: resolved IP address and its class; negotiated TLS version and cipher suite; leaf
subject, issuer and validity window; leaf SPKI SHA-256, rendered in grouped hex so a human can
actually compare it; the trust anchor kind; and Certificate Transparency status for publicly
trusted chains. All of it must survive Dynamic Type at accessibility sizes and be read correctly
by VoiceOver (R-64) — a fingerprint that VoiceOver reads as an undifferentiated hex blob is not
a comparison surface, so it needs an explicit grouped reading.

**Part 3 — Dry-run preview.** The exact bytes the export path would emit. The enforcement point
is that the preview **calls the production encoder** — there is no second serialiser. A test
captures the wire bytes for a fixed input and asserts they are identical to the preview bytes.
Credential *values* are masked; credential *header and field names* are shown, because "which
token goes where" is exactly what a user configuring an unfamiliar endpoint needs to check.
Per-protocol, "the payload" means: the full request line, headers and body for HTTP; the topic,
retain flag, QoS and payload for MQTT; the filename and file contents for local file and the
companion.

**Part 4 — Pin-on-first-use with halt-on-change.** At the confirmed first connection, record the
leaf SPKI digest and the issuer SPKI digest. Default policy is **leaf pin**; the user may opt a
destination into **issuer pin** so that routine leaf rotation under their own CA does not prompt
— an explicit, per-destination, ledger-recorded choice, never a default, because it is strictly
weaker.

On mismatch: **halt**, before any health data is written to the socket. Halt is a persisted
destination state, survives relaunch, fires an R-40-class notification, shows in the widget, and
requires explicit re-approval on a screen showing old and new fingerprints side by side with the
dates each was first seen. A network failure, DNS failure or timeout is **not** a pin change and
must not be conflated — conflating them trains users to click through the one prompt that
matters.

---

### R-32 — The network allowlist and its enforcement point

**The enforcement point is a single transport module.** Every outbound connection in the product
— HTTPS, MQTT, the companion, the advisory fetch — originates in one module. That is the whole
design; everything else supports it.

**Making it the only path.** Access control alone cannot do this in Swift, because any target
can reach Foundation's networking. So:

1. A CI static check over the source tree fails the build on any reference to a
   connection-initiating API (`URLSession`, `URLRequest` execution, `NWConnection`,
   `NWBrowser`, `NWListener`, raw sockets) outside the transport module and its tests.
2. The transport module and that check's allowlist are CODEOWNERS-protected (SEC-47).
3. Any PR that changes the check's allowlist, the transport module, or the set of reachable
   hosts/ports/protocols is automatically labelled and requires security review (SEC-58's
   "egress diff", promoted here from Should to a required check, because with three protocol
   families in scope it is doing real work).

**The gate itself, in order.** Ordering matters because a DNS lookup for a disallowed host has
already leaked the hostname:

1. Match the **configured host string** against the allowlist before any resolution.
2. Resolve.
3. Re-check the **address class** at connect time, on every connection (SEC-15). A destination
   configured as private that now resolves publicly **fails closed** and raises an alert. This
   is the single most likely control to be dropped during implementation, so it gets its own
   named test and its own ledger outcome value.
4. Apply the destination's trust policy (public CA, imported anchor, or pin) and the pin check.
5. Connect.

**Allowlist membership** is exactly: the user's configured destinations, plus one built-in entry
— the R-38 advisory endpoint, which is displayed in the UI, printed in the README, and
user-disableable. There is no second built-in entry and no mechanism to add one at runtime
(SEC-40: no remote configuration).

**The acceptance criterion needs fixing.** R-32 says a network capture must show zero traffic to
a removed host. A raw capture will also show DNS queries, OCSP/CRL fetches and CT log traffic
initiated by the *system* trust evaluator on our behalf, to hosts that are not on the allowlist
and never can be. The criterion must be scoped to **application-initiated connections**, with
the OS-initiated set enumerated and excluded by name in the test harness. See §*Requirements I
cannot secure as written*.

---

### R-33 — Credential storage and verified backup exclusion

**Storage.** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable`
false, in a dedicated access group, one item per destination
(<https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility>).
The rationale is Stage 1's and unchanged: `WhenUnlocked` breaks background export, and
`ThisDeviceOnly` is what makes T-17 non-exploitable.

**One addition Stage 1 did not make.** Keychain item *attributes* are queryable metadata, and a
hostname is health data by inference (A3). So the item's service and account attributes must be
an **opaque destination UUID**, never the hostname, label or URL. The hostname lives in the
encrypted configuration store with the rest of the destination record.

**Backup exclusion, and what "verified" means.** `ThisDeviceOnly` covers Keychain items. Files
do not inherit that and need `NSURLIsExcludedFromBackupKey` on every directory holding queued
payloads, caches, logs, traces or key material — set at directory creation and **re-asserted at
every launch**, because a migration or a restore can recreate a directory without it.

R-33 says "verified by taking an actual backup", and I want that to be a procedure rather than
an intention:

- **Per release, automated part.** Seed the device with a canary credential value, a canary
  queued payload and a canary log line. Take an encrypted local backup. Walk the backup tree
  *including the manifest database*, and assert zero canary hits. The walk and the grep are
  scripted; only the "take a backup" step is manual.
- **Per minor release, manual part.** iCloud backup, restore to a second device, and assert:
  zero credentials present, zero queued payloads present, and the SEC-64 disclosure
  ("credentials do not migrate") is shown before the user is asked to re-enter anything.

**Defence in depth.** A Secure Enclave-generated P-256 key wraps the symmetric key that
encrypts the credential blob and the outbound queue (SEC-66). This binds the container to the
device, so a copied container is inert. It is *not* protection against an attacker holding the
unlocked device, and we must not describe it as such.

**iCloud Keychain sync** stays a per-destination explicit opt-in with the blast-radius warning
(SEC-34), never a default and never enabled by a migration. New in Stage 2: **enabling it is an
R-40 security event**, because it is precisely the action a coercer with a shared Apple ID would
take to inherit working credentials on their own hardware.

---

### R-35 — The ATS exception path

**Private CAs are not an ATS problem and must not be solved with an ATS key.** ATS governs TLS
parameters; server-certificate trust is a separate evaluation an app may legitimately perform
(<https://developer.apple.com/documentation/security/preventing-insecure-network-connections>).
A user-imported anchor, scoped to one destination, evaluated in our transport module, yields
full-strength TLS with no `Info.plist` exception and no App Review justification — and is
*stronger* than public-CA trust, because it defeats system-trust MITM (T-05).

Design: the anchor is stored in the destination record; trust evaluation for that destination
uses that anchor **only**, not the system store plus the anchor. Fingerprint and subject are
displayed at import and re-displayed on any change. A test asserts an anchor imported for
destination A does not validate destination B.

**Plain-HTTP LAN endpoints** use `NSAllowsLocalNetworking` as the *sole* ATS key, under all five
Stage 1 conditions. Two Stage 2 additions:

- **The type carries the concession.** An insecure-LAN destination is a distinct kind whose
  construction requires a risk-acknowledgement value carrying the typed confirmation phrase, the
  timestamp, and the ledger entry identifier. It cannot be constructed by a migration, a config
  import, a URL scheme or a default (SEC-17/18). "Never the default" becomes "not
  representable as a default".
- **The unverified premise gets a test and a fallback.** Stage 1 flagged, and did not assert,
  whether `NSAllowsLocalNetworking` covers RFC 1918 IP literals as well as `.local` and
  unqualified names. Verification method: `nscurl --ats-diagnostics` against the built app's
  ATS configuration, plus a live connection test to `http://192.168.x.x:PORT` from a device
  build, on the minimum supported OS and the current one. **If it does not cover IP literals,
  the consequence is decided now rather than late:** the supported plaintext form is `.local`
  and unqualified names only, IP-literal endpoints require TLS, and the self-hoster
  documentation says so. We do not widen the ATS key. Ever (SEC-19).

**Build gate.** CI parses the **built** `Info.plist` on every commit and fails on any
`NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsForMedia` or `NSAllowsArbitraryLoadsInWebContent`
key, and asserts that `NSAllowsLocalNetworking` is the only ATS exception present.

---

### R-43 — Delete-all

**Crypto-erase first, then delete.** Order is the design:

1. Destroy the Secure Enclave wrapping key. Everything encrypted under it — credentials, queue,
   ledger body — is now unrecoverable, even if the process dies at this instant.
2. Delete Keychain items by access group, per item class.
3. Walk and delete the app container, App Group container, URL caches, temporary directories,
   the queue store, the journal, pinned SPKI records, imported CA anchors and companion pairing
   material.
4. Remove the `UserDefaults` suite.
5. Write the successor ledger's **genesis marker**: previous chain head, count of destroyed
   entries, the earliest and latest destroyed timestamps, and the wall-clock time of destruction.

Step 5 is the anti-coercion property (T-51). A coercer who wipes the ledger to hide the
destination they added leaves behind: *"1,847 egress records covering 14 March 2026 to 2 September
2026 were destroyed on 2 September 2026 at 21:14."* They cannot delete that without triggering it
again.

**Idempotent and verifiable.** A second run reports zero of everything. Verification is
post-action Keychain enumeration by access group returning zero items, plus a container walk
asserting no file matches the payload/log/ledger globs, plus a user-visible report of what was
destroyed.

**Authentication.** Delete-all requires device unlock and nothing more. A victim under duress
must be able to use it immediately; gating it behind an additional secret would be a
victim-hostile design, and the genesis marker is what makes the coercer's use of it survivable.

**macOS.** The companion has its own delete-all, and the uninstall documentation covers manual
login-keychain removal, because macOS keychain items outlive a dragged-to-Trash app bundle.

---

### R-44 — Purge on authorisation revocation

**This requirement cannot be met as written, and the reason is a deliberate Apple design.** The
app cannot determine whether read authorisation was granted or denied: Apple states that denial
is indistinguishable from absent data, precisely so that an app cannot infer a sensitive
condition from a refusal
(<https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>). That
is the same guarantee R-60 is built on. There is no callback, no status query, and no observable
event at the moment a user revokes read access for a type. A 60-second clock starting at the
revocation event therefore has no start signal.

**What is achievable, and what I propose R-44 becomes.**

1. **Purge on the events we can observe**, within 60 seconds of each: every user-visible
   foreground activation, every background wake, and — the one genuinely reliable signal —
   the user deselecting a type inside our own app. The last case is testable to the second and
   should carry R-44's acceptance criterion.
2. **Bound the exposure structurally rather than reactively.** Delete on successful delivery;
   a hard TTL on undeliverable payloads (SEC-62; the value is still unset — see §*Open
   questions*); the R-09 size cap. A queue that holds nothing for long is a better answer to
   revocation than a fast purge on a signal that does not exist.
3. **Index the queue by HealthKit type** so a per-type purge is a supported operation rather
   than a full-queue scan, which is what makes (1) cheap enough to run on every wake.
4. **Do not infer revocation from empty reads.** A type returning zero rows is R-60's
   both-causes case and must never be reported as denial.

Proposed restatement is in §*Requirements I cannot secure as written*.

---

## Anti-coercion controls

The threat, restated because it is the reason these exist: an abusive partner with a few minutes
of physical access and the passcode configures a destination they control, and the victim's
sleep, cycle, mental-health and location-adjacent data flows to them indefinitely. This app is an
excellent stalkerware payload. R-30's ledger records the exfiltration faithfully and reports to
nobody. R-40 and R-41 are what make the difference.

**The design constraint that shapes everything below:** the adversary holds the passcode. There
is no secret we can keep from them, no surface we can write that they cannot read, and no
setting we can protect that they cannot change. So the goal is not prevention. The goal is:
**a victim who looks will find the truth, suppression leaves marks, and no version of this app
ever helps a coercer stay hidden.**

### R-40 — Notification on destination add or re-point

**Triggering events.** Destination created; destination re-pointed (host, port, path, topic or
credential changed); pin re-approved after a change; an ATS exception granted; the export scope
widened to include a sensitive type class (R-66); iCloud Keychain sync enabled for a
destination; the advisory channel disabled; the ledger destroyed. All of these are the actions a
coercer takes, and all of them are rare enough in legitimate use that notifying on every one
costs the honest user almost nothing.

**Delivery.** `UNNotificationInterruptionLevel.timeSensitive`, which breaks through Focus modes
and scheduled summary delivery and requires only the Time Sensitive capability
(<https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel>).

I considered and **recommend against** the Critical Alerts entitlement. It bypasses the ringer
switch and Focus entirely, Apple grants it case-by-case for health, safety and emergency use, it
requires a separate runtime opt-in the user can revoke, and it adds an approval dependency to
our release path
(<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>).
Against a coercer who can simply open Settings, it buys nothing the escalation chain below does
not.

**The notification is not the record.** This is the load-bearing idea. A coercer can swipe a
banner away in one second. So every triggering event creates a persistent **unacknowledged
security event**, and:

- Dismissing the notification does **not** acknowledge the event.
- Acknowledgement requires an explicit action inside the app, and the acknowledgement itself is
  a ledger entry with a timestamp.
- An event stays surfaced for a minimum of **seven days and three distinct user-visible
  foreground launches**, whichever is longer, even after acknowledgement. A coercer who
  configures a destination and acknowledges the event has not cleared the trail; the victim
  opening the app next Tuesday still sees *"a destination was added on 3 September; this was
  acknowledged on this device at 21:14 on 3 September."*

**The escalation chain, and why it has four rungs.** Each rung is a surface a coercer must
separately remember to suppress:

| Rung | Surface | What suppressing it costs the coercer |
|---|---|---|
| 1 | Time Sensitive local notification | One swipe. Assume it is gone |
| 2 | **App icon badge** = count of unacknowledged security events | Must open Settings → Notifications → our app → Badges off. Visible from the Home Screen without opening anything |
| 3 | **Non-dismissible in-app banner** on the root screen | Cannot be suppressed without modifying the binary |
| 4 | **Status widget** (R-23, already Must) gains an unacknowledged-events indicator | Must remove the widget from the Home or Lock Screen, which is itself conspicuous |

**Suppression detection.** On every foreground launch the app reads its notification settings.
If alert, badge or Time Sensitive authorisation was previously granted and is now denied, that
is itself a security event — recorded in the ledger, shown in the in-app banner and reflected in
the widget. Turning our notifications off leaves a mark. This is cheap and it is the closest
thing we have to catching the coercer in the act.

### R-41 — Nothing may ever be hidden

**As a property of our binary, this is enforceable, and here is how.**

1. **No visibility predicate.** The destinations list, the credentials-in-use list and the
   ledger are unconditionally registered routes. There is no conditional around their
   construction. A test walks the navigation tree from a cold launch and asserts all three are
   reachable — and repeats it across a fuzz of the entire settings space, so a future setting
   that happens to hide one of them fails the test.
2. **The settings model is closed and enumerated.** A test iterates every setting and asserts
   none affects reachability of the three routes. Adding a hiding switch requires editing a
   CODEOWNERS-protected file *and* deleting an assertion — two visible acts.
3. **The app-level lock never defines its own secret.** SEC-29's optional gate uses device
   owner authentication — biometrics or the device passcode — and never an app-specific PIN or
   password. This is not a detail: an app-defined password is a gift to a coercer, who could set
   one the victim does not know and thereby lock the victim out of their own ledger. It is also
   all-or-nothing: it locks the whole app, never selected screens, so it cannot be used to hide
   destinations while leaving the rest usable.
4. **No alternate identity.** No alternate app icons, no configurable display name, no
   "discreet" icon set. `CFBundleAlternateIcons` must be absent from the built `Info.plist`,
   asserted in CI on every commit. This is the single most common stalkerware disguise
   mechanism and iOS supports it natively, so its absence must be checked rather than assumed.
5. **No external mutation of visibility.** No URL scheme, universal link, `NSUserActivity`,
   Shortcut, App Intent or config import may change what is displayed (SEC-17).
6. **Feature review gate**, as the PRD requires, at every stage — but as the last line of
   defence, not the first. A gate that depends on a reviewer noticing is exactly what RK-5
   predicts will fail.

**And here is what defeats all of it.** Since iOS 18, anyone who can authenticate to the device
can hide any downloaded app: it disappears from the Home Screen into a Hidden folder at the
bottom of the App Library, gated behind Face ID, Touch ID or **the passcode**, and — the part
that matters most — information from a hidden or locked app "won't appear in some locations…
for example, in notification previews, search, Siri suggestions". Apple documents this in its own
**Personal Safety User Guide**
(<https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>).
Screen Time restrictions can remove an app from view by a different route.

So our threat actor — physical access plus passcode — can defeat R-41 completely with four taps,
using a feature Apple built, and in doing so also suppress rungs 1 and 2 of R-40's escalation
chain. **Whether the status widget survives the app being hidden is unverified and matters
enormously**, because if it does not, the entire escalation chain collapses to a single rung
(the in-app banner, which the victim only sees if they find the app). That is a Stage 2
empirical check with a named owner and a defined method: hide the app on a device running the
minimum supported OS and the current one, and observe whether an installed widget persists,
continues to update, and remains tappable.

**The honest restatement.** R-41 must be a claim about our binary, because that is the only
thing we control:

> *The app contains no mechanism, setting, build configuration, entitlement or alternate
> identity by which its destinations, credentials-in-use or egress ledger can be hidden,
> disguised, password-gated away, or made inaccessible. No stealth or hidden mode, ever. The
> app cannot prevent the operating system's own app-hiding and restriction features from being
> used against its owner; the documented recovery path is Apple's.*

### The out-of-band surface question

The PM asked specifically whether the ledger needs a surface outside the app. I looked at seven
options and I think the answer is genuinely interesting.

| Option | Verdict |
|---|---|
| Notification Center history | No. The coercer clears it |
| Write a receipt to a configured destination | No. That is the destination the coercer controls |
| Email or message a trusted contact | **Refuse.** It requires an outbound channel to a third party and a contact list, contradicts R-37, and creates a new exfiltration path aimed at a person the victim nominated while safe. This is a genuinely dangerous feature, not merely a scope question |
| Mirror the ledger to a second "witness" destination | No. A coercer with the passcode deletes it, and it is a new egress path |
| A second copy in an OS surface we can write to | None exists that is not equally clearable |
| **The Mac companion** | **Partially yes** |
| **Apple's own Settings app** | **Yes, and this is the real answer** |

**The Mac companion is a genuine second-device witness.** D-14 gives some users a second machine
the coercer may not hold. Therefore the pairing channel should carry a **security event stream**,
not just health payloads: the companion keeps its own copy of the ledger chain head and its own
list of destination-change events, and displays them. A coercer who has the phone but not the Mac
cannot clear them. This is a real design contribution from a scope decision that was made for
other reasons, and it is cheap because the transport already exists. It helps only users who have
paired a Mac, which will be a minority.

**Apple's Settings app is the out-of-band surface, and we reach it by documentation rather than
by code.** These are surfaces a coercer cannot forge and cannot easily suppress without leaving
evidence, and a victim can check them without opening our app at all:

- **Settings → Apps → Hidden Apps** — reveals whether our app has been hidden (requires
  authentication, which the victim has).
- **Settings → Privacy & Security → Health** — shows which apps hold read access.
- **Settings → Notifications → [our app]** — shows whether our notifications were disabled.
- **Settings → Privacy & Security → Local Network** — shows whether LAN access was granted.
- **Settings → Cellular / Wi-Fi data usage** — shows that the app has been transmitting.
- **Settings → Privacy & Security → Safety Check** — Apple's own review-and-revoke flow
  (<https://support.apple.com/guide/personal-safety/safety-check-iphone-ios-16-ips2aad835e1/web>).

**Deliverable:** an in-app **Personal Safety** page and a README section, written in plain
language, that walk a user through those six checks and link Apple's Personal Safety User Guide.
This is the honest form of an out-of-band surface for an app in our position, and it is more
useful than anything clever we could build.

### What these controls cannot defend against

Stated once, plainly, because a control catalogue that omits its limits is marketing.

- A coercer with the passcode can add a destination, dismiss notifications, disable them
  entirely, acknowledge security events, destroy the ledger, hide the app, restrict it via
  Screen Time, or uninstall and reinstall it clean.
- A coercer with the victim's Apple ID can enable iCloud Keychain credential sync for a
  destination and inherit working credentials on their own hardware. We make that an R-40 event;
  we cannot prevent it.
- An employer with supervised-device MDM can install us, configure us and suppress our
  notifications through managed settings, and the victim may be unable to remove the app at all.
  **We have no defence.** Where a managed app configuration is readable we show a persistent
  "this device is managed by an organisation" banner; its absence proves nothing.
- Nothing here helps a victim who does not look, and nothing here survives an adversary with
  continuous device access.
- Nothing here addresses the far more common case, which is not our app at all: a shared Apple
  ID, Find My sharing, or a family location setting working exactly as designed. The Personal
  Safety page should say so, because sending a frightened user to check the wrong thing is worse
  than sending them nowhere.

What we do achieve: coercive configuration of this app requires physical access, the passcode,
and the suppression of four independent surfaces, at least two of which leave a dated record of
their own suppression. That is a meaningfully worse tool for a coercer than the same app without
these controls, and it is a great deal less than "protected".

---

## The advisory channel

R-38 exists because AR-F-01 was right: a health app with no way to tell users about a
vulnerability is a health app that cannot discharge the one duty it will certainly acquire. It
is also, structurally, the crack through which "never phones home" is most likely to be widened.
The design below is shaped more by the second concern than the first.

### Shape

A **static, signed feed at a fixed URL**, fetched by an unconditional `GET`, parsed, verified,
filtered client-side and displayed. No server-side logic of any kind exists at that origin, and
the project commits to that in the ADR, the README and the privacy policy.

**Signing and verification.** Detached Ed25519 signature over a canonical serialisation of the
feed. The verification key is **compiled into the binary**, not fetched, not TLS-derived, not
CA-anchored. Two keys are pinned — an active key and a successor — and rotation happens only by
shipping an app update. A feed-driven key rotation would be a takeover primitive and must not
exist. The private key is held offline on a hardware token by a release maintainer; signing is a
deliberate manual act, which is appropriate for something published a handful of times a year.

TLS is used for transport, but the security of the channel does not depend on it. A hostile CA,
a hostile CDN or a hostile network cannot forge an advisory; they can only withhold one, which
is T-44 and is handled next.

**Replay, rollback and suppression (T-44).** The feed carries a monotonically increasing
sequence number, a `valid_from` and an `expires_at`. The client refuses any feed whose sequence
is lower than the highest it has seen, and any feed past its expiry. The feed is **re-signed and
republished on a fixed cadence even when empty** — a heartbeat. A client that has not verified a
fresh signature in 30 days displays *"security advisories are stale"*, which distinguishes
"there is nothing to tell you" from "someone is preventing us telling you", and incidentally
detects our own abandonment, which feeds R-107's maintenance status.

**Content model, and the second structural guarantee.** An advisory carries: identifier, publish
date, severity, affected version range, plain-language description, and a URL displayed **in
full** for the user to visit themselves. That is all. It carries **no field that maps to app
behaviour** — no feature flags, no settings, no destination changes, no "disable export until
updated", no minimum version enforcement. A test asserts that the parsed advisory model is
consumed only by presentation code. Export never depends on advisory reachability, so the
endpoint can never become a kill switch (T-43). This closes the more dangerous of the two
failure modes and is the one nobody asked for.

### The structural guarantee that it cannot become telemetry

The question the PM asked is the right one: *what stops a future contributor adding a query
parameter?* Six things, in descending order of how much I trust them.

**1. A golden-request byte fixture, checked on every commit.** This is the answer. The CI test
stands up a loopback recorder, triggers the advisory fetch, serialises the entire outbound
request — method, path, HTTP version, the complete header set with values, body length — and
compares it byte-for-byte against a fixture committed to the repository. Any added query
parameter, any `If-None-Match`, any cookie, any body, any change in `User-Agent` granularity
fails the build and produces a diff. Fixing the build requires editing the expected-request
fixture, which lives in a CODEOWNERS-protected path and produces a reviewable diff that says,
in plain text, exactly what new information the app would send. That is precisely the visible,
argued act we want, and it is the mechanism SEC-37 uses for telemetry attributes, applied here.

**2. The endpoint is a static object; the client filters, the server never selects.** There is no
API to add a parameter *to*. Version-specific applicability is computed on device against the
full feed. This is the architectural version of the guarantee: even a contributor who wanted to
learn something has nothing to learn it with.

**3. Coarse version granularity.** `User-Agent` carries the marketing version only — major and
minor. No build number, no OS version, no device model, no locale. A build number would narrow
the anonymity set to near-identifiability for a project with a low-thousands user base.

**4. No caching identifiers.** Ephemeral session configuration, no cookie storage, no URL cache,
and specifically **no conditional requests**. An `ETag` is a tracking primitive and is the most
plausible accidental route from "efficient" to "identifying"; it is worth naming because a
performance-minded contributor will add one in good faith. The file is small; fetch it whole.

**5. Timing that does not fingerprint.** At most once per 24 hours, only on user-visible
foreground launch, never on a background wake and never on export, with a random 0–120 second
delay after launch so the request does not correlate precisely with app-open time.

**6. Ledger and control.** Every fetch attempt and outcome is an egress-ledger entry with the
same fields as any destination. The channel is disableable with one switch; when off, no fetch
ever occurs, and the app displays *"security advisories are off — last checked [date]"*
persistently, because a silently disabled safety channel is worse than none.

### Failure mode when unreachable

**Fail open and visible.** A failed fetch never blocks, delays, or degrades export — that
property is what stops the endpoint becoming a dependency and then a kill switch. The failure
is recorded in the ledger, retried at the next eligible launch with no aggressive backoff, and
surfaced through the staleness indicator described above. There is no error banner on a single
failure, because training users to ignore a red badge is how the thirtieth failure gets ignored
too.

### What this honestly discloses

The fetch tells whoever operates or observes the origin: an installation of this app, at this IP
address, on this date, running approximately this version. That is not nothing. It is why the
version is coarse, why the channel is user-disableable with the reason stated, why the endpoint
is printed in the UI and README so users can block it at their own resolver, and why §*Regulatory
posture* treats the origin's access logs as the most legally consequential thing this project
operates.

---

## LAN surfaces: MQTT and the Mac companion

### MQTT

**Transport and trust.** TLS required by default, port 8883, TLS 1.2 floor with forward secrecy,
pin-on-first-use on the broker leaf SPKI — the same implementation used for HTTPS, not a second
one. A plaintext broker on the LAN takes the R-35 path exactly: same insecure-LAN destination
kind, same typed confirmation, same connect-time address-class re-check, same permanent
"insecure" marking in the destination list and the ledger. There is no MQTT-specific concession.

**Broker authentication.** Username and password stored per R-33, or **mutual TLS with a client
certificate**, which is the recommended path for self-hosters because they already run a CA.
Where the broker supports it, we offer a Secure Enclave-generated client key with an exportable
CSR (SEC-67) — this is the one place SE-backed credentials genuinely apply, because we generate
the key. A user-supplied PKCS#12 identity cannot be imported into the Secure Enclave and we must
not claim it is (SEC-68).

**Topic-level authorisation is the broker's job and we must say so.** We cannot enforce an ACL we
do not control. What we control is the shape of what we publish: a deterministic namespace under
a user-set prefix, per-destination type and date-range minimisation (SEC-16), and a
dry-run preview that shows the exact topic, payload, QoS and retain flag before anything is
enabled.

**Publish-only, and this is a security property, not a simplification.** The client subscribes to
nothing. A hostile broker therefore has no inbound channel to us — no commands, no configuration,
no parser surface beyond CONNACK and PUBACK. Home Assistant MQTT discovery is publish-only, so we
lose no functionality. Enforcement: the MQTT adapter exposes no subscribe operation, and a CI
check asserts the subscribe entry points of whatever transport we use are unreferenced.

**Retained messages default off for data topics.** A retained health payload sits on the broker
indefinitely and is delivered to every future subscriber, including ones added by someone else
later (T-35). Retain is permitted for Home Assistant discovery/config topics, which carry no
sample values, and is displayed per destination.

**Quality of service.** Default QoS 1, matching R-03's at-least-once contract. QoS 0 is
permitted but a QoS 0 destination can never report `success` under R-21 — its best outcome is
`unknown_ack`, its test result is `Sent, unconfirmed` per R-25, and it can only reach `enabled`
through the unverifiable-delivery acknowledgement described under R-31.

**Metadata hygiene.** The client identifier must be randomly generated per destination and
stored with it — never derived from device name, model, user identity or hostname, all of which
are handed to the broker in cleartext at CONNECT even under TLS. Clean start with session
expiry zero, so the broker holds no queued state about us; our own queue is the durability
mechanism. **Last Will and Testament is off by default** — an LWT broadcasts our device's
online/offline transitions to every subscriber, which is a presence oracle nobody asked for.

**What a hostile broker gets:** everything published to it, which is inherent — it is the
destination. Plus connection timing and volume. **What a hostile LAN gets under TLS:** the
broker address, SNI, packet timing and volume. Under the plaintext concession: everything, which
is why the concession requires a typed phrase and permanent marking.

### The Mac companion, and whether "outbound push" survives scrutiny

**The claim under test:** the companion reintroduces a LAN surface, but as an outbound push to a
paired device rather than a listening server on iOS, so Stage 1's disqualifying finding does not
apply.

**What survives.** The disqualifying finding was T-11 and it was specific: on iOS, network access
is not permission-gated but HealthKit is, so a loopback listener hands every co-resident app an
unprompted read of the health record, and there is no way to attribute a loopback peer to a
specific app. The companion puts **no socket in a listening state on iOS**. T-11 does not arise.
That part of the framing is correct and it is the part that mattered.

**What does not survive.** The framing is doing more work than it can carry if it is read as
"the product has no listening server". It has one. It is on the Mac, it is always on, and Stage 1
said explicitly that a macOS listener is defensible only behind **all seven** of SEC-02's
controls, and that this was a Stage 2 conversation. This is that conversation, and the seven
controls now bind. Three further consequences the framing conceals:

**(a) The most consequential health-data exposure in the product is now a folder on a Mac.** The
companion writes a decrypted archive outside HealthKit's protection domain, on a machine with
multi-user accounts, Spotlight indexing, Time Machine, and — critically — iCloud Desktop &
Documents sync, which is enabled by default for many users. If the chosen folder is
iCloud-synced, then **our app**, unattended and repeatedly, is storing personal health
information in iCloud. That is not PC-3's user-in-Apple's-own-picker argument: PC-3 rests on a
one-time, per-write, user-initiated document-picker interaction, and the companion has none of
those properties. C-05 and Guideline 5.1.3(ii) are in play (T-39).

Design response: the companion refuses an iCloud-synced destination folder by default, detects
the common cases (paths under a synced Desktop or Documents, and iCloud Drive paths), and
requires an explicit named-risk override that is recorded in the ledger. I recommend this be
covered by the pre-submission App Review enquiry the PM already owes on the PC-3 question, and
flagged in the R-112 opinion.

**(b) Local Network privilege now binds on both ends.** iOS requests it only when a LAN
destination is configured (SEC-03). On macOS 15 and later, third-party apps that interact with
local-network devices must be granted the privilege, it is keyed to the app's code signature,
and there is **no way to reset it to undetermined** on macOS — so a signing-identity change
strands the grant (Apple TN3179,
<https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>;
Apple, *What's new for enterprise in macOS Sequoia*, <https://support.apple.com/en-la/121011>).
Design response: the companion is a normal user-launched app with a menu-bar presence, **not** a
`launchd` daemon or a short-lived agent — the documented failure mode where the privilege prompt
never appears affects exactly those shapes.

**(c) The listener's controls have to be real, so here they are mapped.**

| SEC-02 control | Companion design |
|---|---|
| 1. Mutual TLS or a ≥128-bit out-of-band token | **Mutual TLS**, both identities generated on-device, both pinned. No bearer tokens |
| 2. Self-signed certificate with SPKI pinned at pairing | Yes, both directions. Change on either side ⇒ halt and re-pair in person |
| 3. Off by default; visible indicator while listening; idle shutdown | Off until paired. A menu-bar item is present **whenever the listener is open** and cannot be hidden — R-41's principle applied to macOS. Listener runs only while the user is logged in |
| 4. No advertisement before pairing | Refined: advertise a **generic** service type with an opaque TXT payload, **only during a user-opened, time-boxed pairing window**. Never in steady state. Manual address entry is the primary path |
| 5. Refuse or equally authenticate loopback | **Now satisfiable**, unlike on iOS. A loopback peer must present a pinned client certificate it cannot obtain. Item 5 was unsatisfiable on iOS because there was no authentication story; with mandatory mTLS there is one |
| 6. Host allowlist, reject `Origin`-bearing requests, rate limiting | **Structurally eliminated instead:** the wire protocol is not HTTP, and the client-certificate handshake completes before any application byte. A browser cannot present a client certificate it does not have, so DNS rebinding (T-10) has nothing to talk to. Per-peer rate limiting still applies |
| 7. Every served request in the ledger | Both ends append. The companion keeps its own chain |

**Pairing and trust establishment.** The moment everything else depends on.

- Both devices generate a key pair. On iOS and on Apple silicon Macs the key is Secure
  Enclave-generated and non-exportable; on Intel Macs it lives in the login keychain at
  `AfterFirstUnlockThisDeviceOnly` with an ACL bound to the signed app, and the residual
  extraction risk (T-40) is documented rather than hidden.
- The devices establish TLS with their self-signed certificates and derive a **six-digit
  short authentication string** from the channel transcript and both certificate fingerprints.
  Both screens display it. The user confirms they match, on **both** devices. Only then does each
  side pin the other's SPKI.
- There is **no "continue anyway"**. A mismatch is a hard stop, because a mismatch is a MITM
  (T-38) and the entire security of the channel is this one comparison.
- A QR code displayed on the Mac and scanned by the iPhone is offered as a convenience path
  carrying the same fingerprint, but the SAS comparison is the primary design because it is
  accessible — a camera-only pairing flow fails R-64 for a blind user, and a six-digit code read
  by VoiceOver does not.
- I chose SAS-over-TLS deliberately over a PAKE: it is sound, it uses primitives already in the
  platform, and it does not add a cryptography dependency to a project whose whole dependency
  budget is one library.

**Unpairing** is available from either end, destroys the pinned identity and the key material,
and is a ledger event on both.

**What an attacker on the same network sees.** After pairing: that two devices exchange data
periodically, how much, and when. Not the content. Timing and volume are not mitigable and we do
not claim otherwise (T-07). During the pairing window: a generic Bonjour advertisement with an
opaque payload, and the fact that a pairing is happening. Before pairing: nothing.

**AGPL §13.** ADR-0001 notes that the companion "interacts remotely through a computer network".
Operator and user are the same person, so §13 is inert in the intended deployment. It is not
inert if someone runs a modified companion receiving other people's phones. Cheap discharge: the
companion displays its version and a source URL in its About panel and menu-bar menu.

---

## Redaction as a build-enforced property

RK-5 rates erosion of these requirements High/High and calls it the default outcome. R-51's
answer is a canary test. My concern is narrower and more specific: **a canary test that has
quietly stopped testing anything is indistinguishable from a passing one**, and that is how this
requirement will actually die. So the design has two halves — the enforcement, and the thing that
proves the enforcement still works.

### Tier 1 — Make the unsafe thing unrepresentable

- **Keys are a closed enumeration.** Every telemetry and log emission API accepts a
  `TelemetryKey` value, never a free string. An unlisted key is a compile error, not a test
  failure. The enumeration lives in one CODEOWNERS-protected file, and its permitted membership
  is Stage 1's V-3 list: counts, byte sizes, durations, retry counts, coarse outcome enums,
  protocol names, HTTP status classes, TLS version, and an opaque per-destination random
  identifier — never a hash of the hostname, because a hash of a guessable name is not an
  anonymisation.
- **Values are constrained by conformance.** Only a small, enumerated set of types may be
  attached to a telemetry key. Health values, hostnames, topics, URLs, user labels and
  credential material are carried in a wrapper type that does not conform, has no string
  conversion, and renders as a fixed placeholder in any debug description.
- **Who may conform is itself checked.** A contributor can always write a new conformance, so a
  CI check enumerates all conformances to the telemetry-safe protocol and compares them against a
  committed list in the protected file. Adding one is a reviewable diff.
- **Errors are mapped before they are recorded.** No `Error`, `NSError`, decoder message or HTTP
  response body reaches any sink verbatim; everything passes through a closed enum of
  project-defined codes first (SEC-38). This is Stage 1's "single most valuable test in the
  security suite" and it stays that.

### Tier 2 — The canary, and the sinks it must cover

R-51 already specifies the canary payload: a seeded token, hostname `clinic.example.org`, a
sample value, and source name `Dexcom G7`. Two additions.

**Sink coverage is asserted, not assumed.** The most likely way a leak escapes the canary is
through a channel the harness does not watch. So every type capable of writing outside the
process conforms to a sink protocol, and a test enumerates all conformances and asserts each is
registered with the canary harness. Adding a new sink without registering it fails the build.
The current set: `os.Logger`, the R-20 journal, the R-30 ledger's export path, the R-26
diagnostic bundle, the R-53 OTLP exporter, crash-time last-words state, `UserDefaults`, the
pasteboard, and both LAN transports.

**A binary-level backstop.** After the fixture corpus runs, CI greps the built product's string
sections for the canary values. This catches static leakage that no runtime sink test would see.

### Tier 3 — Proving the canary can still go red

This is the part that answers RK-5 rather than restating it. CI maintains a small corpus of
**leak mutants** — deliberately broken variants of the redaction layer, each introducing one
known leak: an added string interpolation of a sample value, an unwrapped sensitive type, a
verbatim error description, an added attribute key, a hostname in a log line. The job applies
each mutant in turn and asserts the canary test **fails**. If any mutant passes, the build fails
with "the canary test no longer detects [X]".

A green canary proves nothing on its own. A green canary plus a red mutant suite proves the thing
we actually care about. If the security test budget is ever cut to one job, this is the one to
keep, because it is the only one that defends the others.

### Making it fail the build rather than failing review

1. The canary test and the mutant suite are **required status checks** on every PR and every
   push to `main`, running on the secretless, fork-safe CI path (R-85) so a fork PR exercises
   them too.
2. Branch protection prohibits administrator bypass of required checks. If a maintainer can
   merge past it at 2 a.m. before a release, it is a review gate wearing a CI costume.
3. CODEOWNERS on the key enumeration, the conformance list, the sink registry, the mutant corpus
   and the golden fixtures — with security-maintainer review required (SEC-47).
4. The R-26 diagnostic bundle's own canary assertion is part of the same harness, so the two
   cannot drift.

### The boundary, defined once

A sink is **egress-capable** if its output can leave the device without an explicit, per-instance
user action gated by R-26's full-contents preview. The redaction allowlist governs egress-capable
sinks. The ledger and the R-69 data browser are not egress-capable and legitimately contain
hostnames and health values; both leave the device only through R-26's preview or the user's own
export action. Anyone proposing a new path out of the device must first say which side of that
line it falls on.

---

## Supply chain and the MQTT dependency review

### The framing needs correcting before the review starts

The PRD says MQTT is "our first and, for v1, only non-Apple runtime dependency". That is true of
the *package we would name* and false of what we would link.

- **MQTTNIO** (Apache-2.0, <https://github.com/swift-server-community/mqtt-nio>) depends on
  `swift-nio`, `swift-nio-ssl`, `swift-nio-transport-services` and `swift-log`
  (<https://github.com/swift-server/sswg/blob/main/proposals/0018-mqtt-nio.md>). That is five
  packages, one of which vendors **BoringSSL** — a large C codebase executing in the process that
  holds A1 and A2 (T-37). And `swift-log` **collides directly with R-50**, which requires no
  `swift-log` dependency in the app target. Adopting MQTTNIO therefore requires either a
  rescoping of R-50 to "our code does not log through swift-log" or a rejection of the library.
  That conflict should be surfaced now, not discovered by the observability engineer in Stage 3.
- **CocoaMQTT** (<https://github.com/emqx/CocoaMQTT/>) is described as MIT in its README but its
  GitHub licence classification is "Other" and CocoaPods reports `NOASSERTION`. Ambiguous licence
  metadata is itself a SEC-51 finding and must be resolved against the actual `LICENSE` file at
  the pinned commit — and, if still ambiguous, in writing with upstream. It also brings
  `MqttCocoaAsyncSocket` and `Starscream`.

### The finding that decides it

**Every third-party MQTT stack brings its own TLS implementation and its own connection
establishment.** That means our R-32 allowlist chokepoint, our connect-time address-class
re-check (SEC-15), our per-destination trust anchors (SEC-22) and our R-31 pin-on-first-use logic
are **not on that code path**. We would either fragment the single enforcement point that the
entire egress story rests on, or reimplement all four checks inside someone else's callback
surface and test them separately — at which point we have written the hard part anyway (T-36).

Against that: MQTT 3.1.1's **publish-only** subset is small. CONNECT, CONNACK, PUBLISH, PUBACK,
PINGREQ/PINGRESP, DISCONNECT. No subscribe, no websockets, no broker-side session management,
no MQTT 5 property system. `Network.framework` supplies TLS with exactly the trust-evaluation
hooks we are already building for R-31 and R-35.

**Recommendation: build a first-party publish-only MQTT 3.1.1 client over `Network.framework`,
and put the burden of proof on adopting a library rather than on avoiding one.** It reuses the
transport we must build regardless, keeps one enforcement point, removes five packages and a
vendored C TLS stack from the process holding the crown jewels, keeps SEC-49's stated v1 target
(zero third-party runtime dependencies in code paths touching A1 or A2) intact, and removes the
R-50 conflict. It costs perhaps a third to a half of the architect's 3 EW estimate for MQTT, and
it saves the cost of mapping and testing four security controls onto a foreign callback surface.
This is a scope decision, so it is the PM's — but the security argument runs one way.

### The review the dependency must pass, if one is adopted

A written artifact filed as an ADR, not a checkbox. Fields, all evidenced at a pinned commit:

| Field | What must be recorded |
|---|---|
| **Licence** | SPDX identifier read from the `LICENSE` file at the pinned commit, not from repository metadata. Every transitive dependency, same standard. **Ambiguity is a rejection** until resolved in writing |
| **AGPL-3.0 compatibility** | Explicitly checked, not assumed. Apache-2.0 is one-way compatible with GPLv3 and AGPLv3 — Apache-2.0 code may be combined into an AGPL-3.0 work, and the combined work is AGPL-3.0 (<https://www.gnu.org/licenses/license-list.html#apache2>). MIT is compatible. GPLv2-only, CDDL, SSPL, BUSL and any source-available licence are **rejections**. BoringSSL's mixed heritage, if `swift-nio-ssl` is in the tree, must be enumerated separately |
| **Maintenance health** | Number of people with push access; is 2FA and branch protection enforced; commit cadence over 24 months; open security issues; time-to-fix for the last three security-relevant issues; bus factor. A single-maintainer upstream is not disqualifying but changes the pinning policy |
| **Provenance** | Are releases tagged and signed; are tags immutable or can they be re-pointed; are build attestations published; is the published artifact reproducible from the tag |
| **Behaviour** | Does it perform network access at build time; does it bundle any telemetry or analytics transport; does it ship unchecksummed binary blobs; does it have a security contact (SEC-51) |
| **Surface actually used** | The exact API subset we call, and whether the unused surface can be excluded from the build |
| **Security-control mapping** | For each of R-31 pinning, R-32 allowlist, SEC-15 address re-check and SEC-22 per-destination anchors: where in the library's callback surface it is enforced, and the test that proves it. **A control with no mapping is a rejection** |
| **Exit plan** | What replacing it costs, and who would do it |

**Pinning and update policy.** Exact version pins with `Package.resolved` committed and verified
unchanged in CI (SEC-50). Because a tag can be re-pointed and a repository can be deleted, the
MQTT dependency specifically is **mirrored into a project-controlled fork**, and updates arrive
as PRs showing the full diff of the mirrored tree. Security updates within seven days of a
published advisory; feature updates only with the maintenance-health section of the review
re-run. Automated vulnerability scanning per PR and weekly, with a named triage owner
(SEC-52) — and the owner is a person, not the project.

### Release signing, notarisation and SBOM

- **iOS.** Signed build provenance binding each uploaded artifact to its source commit and CI
  workflow via workflow OIDC identity (SEC-59). The honest claim boundary stands: auditable
  source and verifiable provenance, never "reproducible binary" (C-09, SEC-83). I will not sign
  off on wording that blurs it.
- **macOS companion.** Developer ID signed, hardened runtime, notarised and stapled, with
  published SHA-256 hashes, verifiable by any user with `codesign --verify --deep --strict` and
  `spctl` (<https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>).
  macOS is where verifiability is actually attainable and we should not squander it. **Whether
  the companion also ships on the Mac App Store is an open question with real security
  consequences** — see §*Open questions*.
- **SBOM.** CycloneDX per release, attached to the GitHub release, covering both products and
  naming the toolchain versions (SEC-80, SEC-82). Precision matters here: CRA **stewards have no
  SBOM obligation** — Article 13(6) is a manufacturer duty. We generate one anyway because it is
  cheap and because it becomes mandatory the moment D-08 changes. Nobody should read our SBOM as
  evidence that we have concluded we are a manufacturer.
- **Two-maintainer release** (SEC-57) is not pursued: D-10 records an
  owner-directed model with no maintainer recruitment. R-107 reports
  `maintained` while the owner actively maintains the product. R-106 and R-108
  preserve the fork and independent-build continuity path without pretending
  shared signing authority exists.

---

## Regulatory posture under a legal entity

Stage 1's analysis assumed an unmonetised project published by a natural person, which put us
outside the CRA entirely. D-03 (organisation enrolment using an existing legal entity with a
D-U-N-S) and D-08 (donations plus actively-sought named sponsorship) both change the inputs. What
follows is the re-run, and then the precise questions R-112 must ask.

### CRA: steward, manufacturer, or neither

Three tests, in order. The project's status is decided by the first one that bites.

**Test 1 — Is the software "placed on the market"?** If yes, the legal person is the
**manufacturer**, full stop; steward status is only available to a legal person *other than* a
manufacturer (Art 3(14)). Commission guidance C(2026) 5252 (adopted 27 July 2026,
<https://kunnus.tech/downloads/eu-cra-commission-guidance-c2026-5252.pdf>) says at ¶61 that FOSS
supported only through donations is unlikely to be placed on the market, and at ¶62 that
donations which *gate* access to binaries, updates or security fixes are de facto equivalent to
charging a price and do place it on the market. R-110 keeps donations ungated, so on the
guidance's own terms we stay off this limb — **but the guidance is reasoning about repositories,
not about a legal entity distributing free software through a commercial app store under its own
trader identity.** I have not found guidance squarely on that fact pattern and I will not assert
a conclusion. It is R-112 question 1.

**Test 2 — If not placed on the market, is the entity a steward?** Steward status requires all of:
a legal person; systematically providing support on a sustained basis for the development of the
software; and the software being **intended for commercial activities** (Art 3(14)). The third
limb is the one people skip. A health-data exporter used by individuals to move their own data to
their own storage is arguably *not* intended for commercial activities — in which case the entity
is neither manufacturer nor steward, and we are out of scope on both limbs even with D-03. That
would be a materially better position than the PRD currently assumes, and it is worth an opinion
rather than a shrug. R-112 question 2.

**Test 3 — What does sponsorship do?** Guidance treats third-party sponsorship as not creating
scope provided results are openly published — the point AR-F-12 established. But named corporate
sponsorship of a legal entity that also holds an organisational App Store enrolment starts to
resemble commercial activity, and the answer plausibly turns on what the sponsor receives.
Acknowledgement and a logo are one thing; roadmap influence, priority support or any gated
artifact is another and would breach R-110 anyway. R-112 questions 3 and 4.

### If we are a steward, what it actually costs

Worth pricing precisely, because the answer is small and that changes the strategy.

Article 24 requires a documented, verifiable cybersecurity policy fostering secure development
and effective vulnerability handling, including a policy encouraging voluntary reporting; and
cooperation with market surveillance authorities on request. Article 24(3) imports Article 14(1)
— notification of actively exploited vulnerabilities — to the extent the steward is involved in
developing the product, plus 14(3) and (8) for severe incidents affecting the steward's own
development infrastructure. Stewards are exempt from CE marking, EU declaration of conformity,
conformity assessment, technical-documentation retention, the Article 13(6) SBOM duty, and — under
Article 64(10) — **administrative fines**
(<https://policy.openssf.org/CRA/stewards-playbook.html>;
<https://www.greenbone.net/en/blog/cra-open-source-software/>; <https://cvdportal.com/cra/article-24>).
Reporting obligations commence **11 September 2026**, eight days from today.

One precision worth carrying, flagged as a contested reading rather than a settled one: at least
one analysis argues Article 24(3) imports 14(1), (3) and (8) but **not** 14(2)'s 24-hour /
72-hour / 14-day schedule, even though ENISA's Single Reporting Platform materials present the
cadence with manufacturers and stewards in a single frame
(<https://stribog.com/blog/eu-cyber-resilience-act-cra-open-source-obligations-self-hosted>).
That distinction changes our incident-response design, so R-112 should confirm it (question 5).

**Engineering recommendation, and it removes most of the urgency: build to Article 24 regardless
of the classification.** SEC-79 (published cybersecurity policy), SEC-84 (`SECURITY.md` with a
private reporting channel, a five-business-day acknowledgement SLA, a 90-day disclosure default,
scope, safe harbour and an explicit no-bounty statement), SEC-85 (a CVD process aligned to
ISO/IEC 29147 and 30111 with a named responder and deputy) and SEC-86 (CVE issuance plus
published advisories plus in-app delivery through R-38) already constitute substantially all of
it. The marginal cost of compliance is close to zero, and doing it unconditionally means we do
not have to be right about a contested classification. What the opinion then genuinely decides is
narrow: whether we must register with ENISA's Single Reporting Platform and pre-establish the
CSIRT path (SEC-87), and what happens if D-08 ever changes.

### What else the entity changes

**FTC HBNR — probability goes up.** Stage 1's honest caveat was that the Rule reaches entities
"engaged in commerce", and that an unmonetised hobby project's status was untested. A legal
entity distributing through a commercial app store is a much easier fit. Treat HBNR as
applicable. R-38 is the notification *capability*; what is still missing is the **runbook**: who
decides that an incident is a "breach of security" under the amended definition, which expressly
includes unauthorised disclosure and not merely intrusion; the consumer-notification content and
timing; the threshold above which the FTC must be notified and media notice given; and who
drafts the advisory (<https://www.govinfo.gov/content/pkg/FR-2024-05-30/pdf/2024-10855.pdf>). The
precise thresholds and the timing arithmetic should be confirmed by the opinion rather than
transcribed by me — R-112 question 7. Note the design irony Stage 1 named and which is now
sharper: privacy-by-design deprives us of the contact details a breach-notification duty assumes,
and R-38 is our only substitute.

**GDPR — we now process personal data, for the first time, and it may be Article 9 data.** This
is the finding I most want the PM to read. R-38's endpoint receives, at minimum, an IP address, a
timestamp and a coarse app version, and the origin is operated by a legal entity. An IP address
is personal data (CJEU C-582/14 *Breyer*,
<https://curia.europa.eu/juris/liste.jsf?num=C-582/14>). And the CJEU has held that data from
which special-category information can be inferred is itself special-category data (C-184/20
*OT v Vyriausioji tarnybinės etikos komisija*,
<https://curia.europa.eu/juris/liste.jsf?num=C-184/20>). "This IP address, on this date, ran a
health-data export application" is exactly such an inference. If that argument holds, the entity
needs an Article 9(2) condition for its own access logs, and none obviously fits except explicit
consent.

Mitigations are cheap and should be adopted whatever the answer: host the feed as a static object
with **access logging disabled** where the provider permits and minimal retention where it does
not; state the arrangement in the privacy policy; keep the version coarse; keep the channel
user-disableable with the reason given; and print the endpoint so users can block it at their own
resolver. R-112 question 6 asks whether this is sufficient and whether the logs are Article 9
data.

**Washington MHMDA** is triggered by *collection* of consumer health data by an entity conducting
business in or targeting Washington, and carries a private right of action through the Consumer
Protection Act — the sharpest tail risk in Stage 1's analysis. We still collect nothing from the
app. The same access-log argument applies here as under GDPR, and points at the same mitigation:
log nothing.

**Unchanged and still binding:** PC-6's medical-device declaration (C-08,
<https://developer.apple.com/news/?id=nyqbfz1y>), DSA trader status against the entity's address
(C-11, R-111, D-13 — improved by D-03, since the published address is now a business one), and
the App Review guidelines generally
(<https://developer.apple.com/app-store/review/guidelines/>). Guideline 5.1.1(ix)'s
"highly regulated field" concern is resolved favourably by D-03.

### What the R-112 legal opinion must ask

Numbered so the answers can be filed against them. Questions 1–5 are CRA; 6–8 are the ones that
did not exist before Stage 2.

1. Does a legal person distributing a **free** FOSS application through a commercial app store,
   under its own name and trader identity, thereby "place it on the market" or "make it available
   on the market in the course of a commercial activity" for CRA purposes — notwithstanding
   guidance ¶61's donation analysis, which addresses repository distribution?
2. If not placed on the market: is an application whose users are individuals exporting their own
   personal health data "**intended for commercial activities**" within Article 3(14)? If it is
   not, is the entity outside the CRA entirely rather than a steward?
3. Does accepting **named third-party sponsorship** (D-08), where sponsors receive acknowledgement
   only and no gated access, influence or priority (R-110), change the answer to 1 or 2?
4. What specific sponsor benefits would change the answer? We need a bright line we can hold, not
   a balancing test we will lose.
5. Does Article 24(3) import Article 14(2)'s 24h/72h/14d schedule for stewards, or only 14(1),
   (3) and (8)? This determines our incident-response design and our ENISA registration posture.
6. Are the advisory endpoint's access logs — IP address, timestamp, coarse app version, for a
   health-data application — **special-category data under Article 9** on the *OT* inference
   reasoning? If so, is disabling access logging at a static origin sufficient to avoid
   controllership, or is a lawful basis required for the transient processing that occurs anyway?
7. Confirm the FTC HBNR analysis under the legal entity: are we a "vendor of personal health
   records"; what triggers notification; and what are the exact consumer, FTC and media
   notification thresholds and deadlines we must design the runbook around?
8. Confirm the current status of New York's Health Information Privacy Act, revived in the 2026
   session and unresolved at Stage 1, and whether it changes anything for a project that collects
   nothing.

Two further items already on the list from Stage 1 and ADR-0001 and still owed: the GPLv3 §7
additional-permission text itself, and — new in Stage 2 — whether the Mac companion writing a
health archive into a user-selected, potentially iCloud-synced folder is materially different
from PC-3's user-in-the-document-picker position under Guideline 5.1.3(ii). The latter may be
better answered by a pre-submission enquiry to App Review than by counsel.

---

## Verification: how each control is tested

"Where" distinguishes what a fork PR can run from what needs hardware or a human.

| Requirement | Property verified | Method | Where |
|---|---|---|---|
| R-30 | Every transmission produces exactly one attempt entry and one outcome entry | Full-cycle test against a local sink; ledger diffed against the journal | CI, fork-safe |
| R-30 | Tamper-evidence | Mutate an interior entry out of band; assert chain verification fails and the UI reports it | CI, fork-safe |
| R-30 | Destruction is recorded | Run delete-all; assert the successor ledger's genesis marker names the count and date range | CI, fork-safe |
| R-31 | Indivisibility | Compile-time: the export sender accepts only `VerifiedDestination`. CI asserts no overload accepts a raw destination | CI, fork-safe |
| R-31 | Canary handshake is mandatory | Attempt a health export from every non-terminal state; assert refusal from each | CI, fork-safe |
| R-31 | Preview fidelity | Preview bytes byte-compared against captured wire bytes for a fixed input, per protocol | CI, fork-safe |
| R-31 | Identity display completeness | UI test asserts all seven fields present, non-truncated, and correctly grouped for VoiceOver | CI (simulator) |
| R-31 | Halt on pin change | Simulated certificate change; assert zero bytes sent, destination halted across relaunch, notification fired | CI, fork-safe |
| R-31 | Network failure ≠ pin change | Induce timeout and DNS failure; assert the destination is not halted and no re-approval is demanded | CI, fork-safe |
| R-32 | No application-initiated traffic to a non-allowlisted host | Full cycle with a host removed, behind a recording proxy; **OS-initiated DNS/OCSP/CT traffic enumerated and excluded by name** | Device, release gate |
| R-32 | Single chokepoint | Static check fails the build on connection APIs outside the transport module | CI, fork-safe |
| SEC-15 | Address class re-checked per connection | Destination configured as `.local`, DNS re-pointed public; assert fail-closed, alert raised, zero bytes | CI, fork-safe |
| R-33 | Keychain attributes | Assert accessibility class, `synchronizable` false, and that no attribute contains a hostname, for every credential written | CI (simulator) |
| R-33 | Backup exclusion | Seed canaries; encrypted local backup; scripted walk of the tree and manifest asserting zero hits | Release gate, manual backup step |
| R-33 | Migration behaviour | iCloud backup, restore to a second device; assert zero credentials, zero payloads, SEC-64 disclosure shown | Minor-release gate, manual |
| R-35 | ATS integrity | Parse the **built** `Info.plist`; fail on any arbitrary-loads key; assert `NSAllowsLocalNetworking` is the only exception | CI, fork-safe |
| R-35 | Anchor isolation | Anchor imported for A does not validate B | CI, fork-safe |
| R-35 | `NSAllowsLocalNetworking` scope | `nscurl --ats-diagnostics` plus a live plaintext connection to an RFC 1918 literal, on min and current OS | Device, one-off spike |
| R-36 / R-37 | No third-party binary dependency; no outbound telemetry | Linked-library audit; clean-install full-session capture | CI + device release gate |
| R-38 | Request shape is exactly as specified | **Golden-request byte fixture** compared on every commit | CI, fork-safe |
| R-38 | Signature, rollback and expiry | Feed with a bad signature, a lower sequence, and a past expiry each rejected | CI, fork-safe |
| R-38 | Cannot alter behaviour | Assert the parsed advisory model is consumed only by presentation code; assert export succeeds with the endpoint black-holed | CI, fork-safe |
| R-38 | Staleness surfaced | Advance the clock 31 days with no fetch; assert the stale indicator | CI, fork-safe |
| R-38 | End-to-end | A test advisory delivered to a real device during release rehearsal | Release rehearsal |
| R-40 | Fires on every triggering event | Parameterised test over the full event list; assert notification, badge, in-app banner and widget all update | CI (simulator) |
| R-40 | Dismissal ≠ acknowledgement | Dismiss the notification; assert the event remains unacknowledged and surfaced | CI (simulator) |
| R-40 | Suppression detected | Revoke notification authorisation between launches; assert a security event is raised and recorded | Device |
| R-41 | Three routes always reachable | Navigation walk from cold launch across a fuzz of the settings space | CI (simulator) |
| R-41 | No setting hides them | Enumerate all settings; assert none affects reachability | CI, fork-safe |
| R-41 | No alternate identity | Assert `CFBundleAlternateIcons` absent from the built `Info.plist` | CI, fork-safe |
| R-41 | OS-level hiding (limits) | Hide the app on device; record whether the widget persists and updates | Device, one-off spike |
| R-43 | Completeness and idempotence | Post-action Keychain enumeration by access group returns zero; container walk finds zero payload/log/ledger files; second run reports zero | CI (simulator) + device |
| R-44 | Purge on the observable events | Deselect a type; assert queued payloads for it are gone within 60 s; assert purge runs on foreground and on background wake | CI, fork-safe |
| R-51 | Allowlist enforcement | Unlisted key fails to compile; conformance list diffed against the protected file | CI, fork-safe |
| R-51 | No leak through any sink | Canary corpus across every registered sink, plus a binary string-section grep | CI, fork-safe, every commit |
| R-51 | **The canary still works** | **Leak-mutant suite: each known-leak mutant must make the canary test fail** | CI, fork-safe, every commit |
| R-51 | Sink coverage | Enumerate sink conformances; assert each is registered with the harness | CI, fork-safe |
| MQTT | Publish-only | Assert no subscribe entry point is referenced; integration test against an ephemeral broker (R-90) | CI, fork-safe |
| MQTT | Retain off for data topics | Broker inspection after a publish; assert no retained data message | CI, fork-safe |
| MQTT | Client ID is random and non-derivable | Assert across fresh installs on differently-named devices | CI (simulator) |
| Companion | SAS mismatch is a hard stop | Simulated MITM at pairing; assert no pin recorded and no "continue" affordance exists | CI + two-device manual |
| Companion | Not browser-reachable | Attempt an HTTP request and a browser fetch against the listener; assert the handshake fails before any application byte | CI, fork-safe |
| Companion | iCloud-synced destination refused | Configure a synced Desktop/Documents path; assert refusal and the override path | CI (macOS) |
| Companion | Pin change halts | Regenerate the Mac identity; assert the iPhone halts and demands re-pairing | Two-device manual |
| Supply chain | Dependency integrity | `Package.resolved` diff check; linked-library audit; SBOM generated and attached | CI, fork-safe |
| Release | Provenance and notarisation | Attestation verifies against the published commit; `codesign --verify --deep --strict` and `spctl` pass on the macOS artifact | Release gate |

Stage 1 named the three tests to keep if only three survive triage: the redaction canary, the
backup inspection, and the connect-time address re-check. Stage 2 changes that answer to four,
and reorders it. **Keep, in order: the leak-mutant suite (because it is what keeps the canary
honest), the redaction canary, the golden-request fixture, and the backup inspection.** The
address re-check drops to fifth only because R-31's type-level indivisibility now protects the
path it guards.

---

## Requirements I cannot secure as written

Six. Each has a proposed restatement, because flagging a problem without a fix is not a
deliverable.

**1. R-44 — the 60-second revocation purge.** Apple deliberately makes read-authorisation
revocation undetectable, so the clock has no start signal
(<https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>).
Proposed: *"Deselecting a type in the app purges that type's queued payloads within 60 seconds. A
purge check also runs within 60 seconds of every user-visible foreground activation and every
background wake. The app cannot detect revocation of HealthKit read authorisation — Apple makes
denial indistinguishable from absent data by design — so exposure between revocation and the
app's next execution is bounded by the queue TTL and size cap rather than by a purge, and the
README says so."*

**2. R-41 — "can never be hidden".** Defeated by iOS 18's own Hide-and-Require-Face-ID feature,
operated by exactly our threat actor, in four taps
(<https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>).
Proposed restatement is in §*Anti-coercion*: a claim about our binary, plus a documented recovery
path through Apple's own Settings surfaces.

**3. R-40 — notification delivery.** As a single mechanism it is defeated by one swipe, by a
Settings toggle, and by app hiding. It is only meaningful as the first rung of the four-rung
chain in §*Anti-coercion*, and the chain's survival depends on the unverified widget question.
Proposed: add *"escalating through badge, non-dismissible in-app banner and status widget;
suppression of any rung is itself recorded as a security event"* to the requirement, and add
*"and with notifications denied"* to its acceptance criterion, mirroring what R-23 already does.

**4. R-32's acceptance criterion.** "Network capture shows zero traffic to it" will fail on
OS-initiated DNS, OCSP/CRL and CT traffic that we neither cause nor can suppress. Proposed:
*"…zero **application-initiated** connections to it across a full cycle, with OS-initiated
resolution and certificate-validation traffic enumerated and excluded by name in the test
harness."*

**5. R-30's "immutable".** On a device its owner controls, the honest property is
tamper-evidence. Proposed wording is in §*Control designs*. This matters beyond pedantry: if the
PRD says immutable, someone will eventually claim it in the README, and it would be false.

**6. R-50 versus MQTTNIO.** If the library route is taken, `swift-log` enters the dependency
graph and R-50's acceptance criterion ("no `swift-log` dependency in the app target") fails.
Either R-50 is rescoped to *"no first-party code logs through a `swift-log` facade; `os.Logger`
is used directly, and any transitively linked logging facade is not used by our code"*, or the
library is rejected. My recommendation makes the question moot.

**And one thing I will not sign off on that is not yet in the document.** The Mac companion
writing a decrypted health archive into an iCloud-synced folder by default. PC-3's reasoning does
not extend to an unattended, repeated, app-managed write to a remembered path. If the PM wants
that behaviour it needs a pre-submission App Review answer first, not a shipped bet.

Stage 1's twelve named refusals stand unchanged, with two Stage 2 additions: **(13)** any
advisory-channel field that can alter app behaviour, and **(14)** any MQTT or companion transport
that bypasses the single allowlist-and-pinning enforcement point without an itemised,
individually tested mapping of every check.

---

## Open questions for the PM

1. **Mac companion distribution — Mac App Store or Developer ID only?** This changes the sandbox
   and entitlement design (`com.apple.security.network.server`), whether Guideline 5.1.3(ii)
   binds the companion contractually, and whether SEC-55's outside-the-store verifiability story
   holds. I need this before the companion design can close. My recommendation: **Developer ID,
   notarised, outside the store** — it is where verifiability is attainable and it removes a
   review surface.
2. **MQTT: first-party publish-only client, or a third-party library?** My recommendation is the
   first-party client for the reasons in §*Supply chain*. This is a scope and cost decision, so
   it is yours. If a library is chosen, R-50 needs rescoping and the security-control mapping
   becomes a required review artifact.
3. **Who operates the advisory endpoint, and can access logging be disabled there?** The answer
   determines whether T-46 is a paper risk or a real one, and it needs to be in the privacy
   policy before launch.
4. **Queue TTL for undeliverable payloads.** Stage 1 Q5, asked and not answered; D-11 settled the
   size cap and eviction but not the TTL. It is now load-bearing for R-44, because with
   revocation undetectable the TTL *is* the exposure bound. I propose 7 days, then delete-and-alert.
5. **Who owns the security-maintainer role, and who is the deputy?** SEC-47, SEC-84 and SEC-85 all
   assume a named person with an acknowledgement SLA, and D-10 records no second maintainer. An
   unowned `SECURITY.md` promises a response nobody has agreed to give. This also blocks
   SEC-57's two-maintainer release rule, which we should not claim to operate until it is true.
6. **Do you accept the restatements of R-44, R-41, R-40, R-32 and R-30?** They make the document
   weaker and truer. I would rather lose the sentence than have it be false.
7. **Who owns the two empirical spikes?** (a) Does the status widget survive the app being
   hidden — this determines whether the anti-coercion escalation chain has four rungs or one.
   (b) Does `NSAllowsLocalNetworking` cover RFC 1918 IP literals — this determines whether
   self-hosters can use `http://192.168.x.x` at all. Both are cheap; both change a design if the
   answer is unfavourable; neither has an owner.
8. **A pre-submission App Review enquiry** covering the companion's folder writes and PC-3's
   original iCloud question, together. Stage 1 recommended this and it was not dispositioned.

---

## ADRs I propose

Numbered from 0002; ADR-0001 exists. Listed rather than written, since the deliverable is one
file.

| ID | Title | What it records |
|---|---|---|
| **0002** | Verified-destination as the sole entry to the export path | R-31's indivisibility as a type-level property; the state machine; the R-83 test-build seam and why it is the only exception |
| **0003** | Tamper-evident egress ledger, not an immutable one | The hash chain, the Secure Enclave seal, the delete-all genesis marker, and the claim boundary we will not exceed |
| **0004** | A single network egress chokepoint | The transport module, the static check that makes it the only path, ordering of allowlist and resolution, and the OS-initiated traffic carve-out |
| **0005** | Advisory channel: static signed feed, display-only, golden-request enforced | Signing and pinned keys, rollback and heartbeat, the byte fixture, and the prohibition on any behavioural field |
| **0006** | MQTT via a first-party publish-only client | The T-36 enforcement-point argument, the dependency-tree finding, the R-50 conflict, and the review template if overruled |
| **0007** | Mac companion pairing and wire protocol | mTLS with SAS-confirmed pin-on-pairing, non-HTTP protocol as a structural anti-rebinding control, and the SEC-02 seven-control mapping |
| **0008** | Redaction enforced by types and by leak mutants | Closed key enum, conformance list, sink registry, and why a green canary is worthless without a red mutant suite |
| **0009** | Anti-coercion posture and its stated limits | The four-rung chain, the R-41 restatement, the Personal Safety page, and an explicit record of what we cannot defend against |
| **0010** | Build to CRA Article 24 regardless of classification | Why the marginal cost is near zero and why that is better than being right about a contested question |

---

## Sources

All URLs retrieved 3 September 2026. Stage 1's 33 sources remain valid and are not repeated;
these are the ones supporting new or changed claims.

**Apple platform and policy**

1. App Store Review Guidelines (5.1.1, 5.1.2(vi), 5.1.3, 2.5.1, 3.2.2(iv)) — <https://developer.apple.com/app-store/review/guidelines/>
2. Authorizing access to health data — read authorisation denial is indistinguishable from absent data — <https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>
3. Preventing Insecure Network Connections — ATS scope; `NSAllowsLocalNetworking` requires no justification — <https://developer.apple.com/documentation/security/preventing-insecure-network-connections>
4. Restricting keychain item accessibility — <https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility>
5. TN3179: Understanding local network privacy — macOS 15+ behaviour, code-signature keying, no reset to undetermined — <https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>
6. What's new for enterprise in macOS Sequoia — local network permission for third-party apps and launch agents — <https://support.apple.com/en-la/121011>
7. `UNNotificationInterruptionLevel` — passive / active / timeSensitive / critical — <https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel>
8. Critical Alerts entitlement request — Apple-granted, case-by-case — <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>
9. Apple Personal Safety User Guide, *Lock or hide apps on your iPhone* — hidden apps require authentication; information from a locked or hidden app does not appear in notification previews, search or Siri suggestions — <https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>
10. Apple Personal Safety User Guide, *Safety Check* — <https://support.apple.com/guide/personal-safety/safety-check-iphone-ios-16-ips2aad835e1/web>
11. Notarizing macOS software before distribution — <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
12. Update on regulated medical device apps (EEA, UK, US), 26 March 2026 — <https://developer.apple.com/news/?id=nyqbfz1y>
13. Protecting access to users' health data — Protected Unless Open; access relinquished 10 minutes after lock — <https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web>

**Regulatory**

14. Commission Guidance on the Cyber Resilience Act, C(2026) 5252 final, 27 July 2026 — donations (¶61–62), steward vs manufacturer (¶74) — <https://kunnus.tech/downloads/eu-cra-commission-guidance-c2026-5252.pdf>
15. OpenSSF / Linux Foundation, CRA Stewards Playbook — Article 24(1)–(3) text and mapping — <https://policy.openssf.org/CRA/stewards-playbook.html>
16. Greenbone, *Cyber Resilience Act open source* — steward duties; 11 September 2026 reporting start; Art 64(10) fine exemption; no CE marking — <https://www.greenbone.net/en/blog/cra-open-source-software/>
17. CVD Portal, *CRA Article 24* — no SBOM obligation for stewards (Art 13(6) is a manufacturer duty); Art 14 applies only where the steward is involved — <https://cvdportal.com/cra/article-24>
18. Stribog, *The Cyber Resilience Act Reaches Your Build Pipeline* — argument that Art 24(3) imports 14(1), (3) and (8) but not 14(2)'s schedule — <https://stribog.com/blog/eu-cyber-resilience-act-cra-open-source-obligations-self-hosted>
19. Thomas Murray — C(2026) 5252 adopted and substantively final, but **expressly non-binding** — <https://cyber.thomasmurray.com/insights/eu-cyber-resilience-act-commission-publishes-implementation-guidance>
20. FTC Health Breach Notification Rule, final rule, 89 FR 47028, effective 29 July 2024 — unauthorised disclosure is a breach — <https://www.govinfo.gov/content/pkg/FR-2024-05-30/pdf/2024-10855.pdf>
21. CJEU C-582/14 *Breyer* — dynamic IP addresses as personal data — <https://curia.europa.eu/juris/liste.jsf?num=C-582/14>
22. CJEU C-184/20 *OT v Vyriausioji tarnybinės etikos komisija* — data permitting inference of special-category information is itself special-category — <https://curia.europa.eu/juris/liste.jsf?num=C-184/20>

**Licensing and dependencies**

23. FSF licence list — Apache 2.0 is compatible with GPLv3 and AGPLv3 (one-way) — <https://www.gnu.org/licenses/license-list.html#apache2>
24. `swift-server-community/mqtt-nio` — Apache-2.0 — <https://github.com/swift-server-community/mqtt-nio>
25. SSWG proposal 0018 — MQTTNIO's dependency set: `swift-nio`, `swift-nio-ssl`, `swift-nio-transport-services`, `swift-log` — <https://github.com/swift-server/sswg/blob/main/proposals/0018-mqtt-nio.md>
26. `emqx/CocoaMQTT` — README states MIT; GitHub licence classification "Other"; CocoaPods reports `NOASSERTION` — <https://github.com/emqx/CocoaMQTT/>

**Not verified, flagged rather than asserted**

- Whether `NSAllowsLocalNetworking` covers RFC 1918 IP literals in addition to `.local` and
  unqualified names. Carried forward from Stage 1; method and fallback specified in §*R-35*.
- Whether a status widget survives, and continues updating, when the app is hidden via iOS 18's
  Hidden Apps feature. This determines whether R-40's escalation chain has four rungs or one, and
  it is the single most consequential unverified fact in this document.
- Whether App Review treats an app-managed, unattended, repeated write into a user-selected
  iCloud-synced folder differently from a one-time document-picker save under Guideline 5.1.3(ii).
  Recommend a pre-submission enquiry.
- The precise FTC HBNR consumer, FTC and media notification thresholds and deadlines under a legal
  entity. Stated in shape only; R-112 question 7 asks for the numbers.
