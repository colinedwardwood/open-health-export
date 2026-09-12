# R-67 / SEC-18 configuration portability

Status: local file contract implemented; signed QR transport deferred.

`CoreDomain` owns a versioned, deterministic `.tributary` JSON representation for
destination configuration. The representation is credential-free by construction:

- credentials are fixed to `omitted`;
- destination-kind settings are allow-listed and contain no secret-bearing fields;
- URL user info and query strings are rejected;
- unknown imported fields are rejected rather than ignored;
- timestamps and other nondeterministic values are absent.

File import is a two-step API. Parsing produces inert review data. Exact typed
confirmation produces only new `disabledRequiresTest` drafts, with no operation that
can update an existing local destination or enable a draft. The app allocates fresh
local identifiers and persists the disabled drafts. HTTPS and MQTT drafts can be
loaded into their existing setup editors only when that kind's local slot is empty;
unsupported settings are refused rather than dropped. The user must supply omitted
credentials and pass the existing probe, identity-confirmation, scope, and enablement
path before the draft is consumed. Local-file, Home Assistant, and companion imports
remain disabled drafts because their runtime setup paths cannot yet preserve the
portable endpoint/settings contract.

The app can export enabled HTTPS and MQTT destinations back to a deterministic
`.tributary` document. It includes the imported local identity when present,
endpoint, supported non-secret settings, and metric/date scope. Credential
material and credential-presence flags are never represented in the document.

Signed QR import remains a **Should** and is intentionally deferred. The product has
not selected a signing authority, trust bootstrap, key rotation/revocation policy, or
ownership model for server-generated configuration keys. No signing keys or implied
trust roots are generated here. When those decisions exist, QR should transport the
same reviewed credential-free document (or a separately versioned signed envelope);
successful signature verification must never bypass review, typed confirmation, or
the destination test.
