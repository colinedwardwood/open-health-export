# Runtime dependency policy

New runtime dependencies must:

1. Be at least 72 hours old on the registry used.
2. Build on Linux, or live only in a target the Linux CI job does not compile.
3. Be compatible with AGPL-3.0 outbound (COPYING).
4. Have an ADR.

v1 admits **zero** third-party Swift packages in `ExportCore`. MQTT is first-party (ADR-0003).
HealthKit, SQLite, Network, and Security are Apple / system libraries.
