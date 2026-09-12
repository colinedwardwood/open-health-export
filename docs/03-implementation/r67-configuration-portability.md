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
can update an existing local destination or enable a draft. The app integration must
still show the full review UI, allocate new local identifiers, collect omitted
credentials, and run the existing real-path destination test before enablement.

Signed QR import remains a **Should** and is intentionally deferred. The product has
not selected a signing authority, trust bootstrap, key rotation/revocation policy, or
ownership model for server-generated configuration keys. No signing keys or implied
trust roots are generated here. When those decisions exist, QR should transport the
same reviewed credential-free document (or a separately versioned signed envelope);
successful signature verification must never bypass review, typed confirmation, or
the destination test.
