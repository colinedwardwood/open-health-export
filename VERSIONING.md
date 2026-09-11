# Versioning

Three independent SemVer 2.0.0 streams. One stream is wrong: the wire format has its own
stability commitment (R-12), independent of the app's release cycle.

| Stream | Scheme | Tag | The public API it governs | MAJOR bump means |
|---|---|---|---|---|
| **App** | SemVer 2.0.0 → `CFBundleShortVersionString` | `v1.4.2` | User-visible behaviour, the destination configuration format, the persisted-state format | A capability is removed, or a state migration is not backward-compatible |
| **Wire spec** | SemVer 2.0.0, independent | `spec/v1.1.0` | Field names, types and semantics; aggregation semantics per metric (R-07); idempotency-key derivation (R-02, R-03) | A field is removed or retyped; aggregation or key derivation changes meaning |
| **HA integration** | SemVer 2.0.0 → `manifest.json` `version` | `ha/v0.3.0` in this repo; `v0.3.0` release in the HA repo | Entity IDs, `unit_of_measurement`, `device_class`, `state_class`, config-entry schema | An entity is renamed, or a config entry is invalidated |

## Five rules

1. **Every app release declares the spec versions it can emit and the one it emits by default**,
   in `spec/compatibility.json` and in the README's support matrix. This is the artifact a
   receiver author reads.
2. **The streams do not imply each other.** An app MAJOR bump does not force a spec MAJOR bump,
   and a spec MAJOR bump does not force an app MAJOR bump — the app can emit two spec versions
   during a transition. That is the entire content of R-12 and it should be stated in
   `VERSIONING.md` in exactly these words, because the default engineering instinct is to couple
   them.
3. **A frozen spec version is immutable.** `policycheck spec-freeze` diffs `spec/vX.Y.Z/**`
   against the committed freeze baseline and fails on any B-class change, including whitespace
   that would alter the published schema. New behaviour goes in a new directory. Within a MINOR,
   changes must be additive and the fixtures from the previous MINOR must still validate.
4. **Build numbers are monotonic and never reused.** `CFBundleVersion` is the CI run number or
   commit count. Apple rejects duplicates, and roll-forward depends on there always being a
   higher number available.
5. **HACS reads the HA repository's latest GitHub *release* tag as the remote version**, and a
   plain tag is not enough — it must be a full release. So the HA stream's tags and its
   `manifest.json` `version` must agree. That agreement is a CI check in the HA repo, which this
   project does not yet publish (HACS remains an external gate).

Current shipping default: app `0.1.0` emits wire `ohe.wire/1` from `spec/v1.0.0` (in-progress
until freeze). See `spec/compatibility.json`.
