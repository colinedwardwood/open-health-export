---
title: Harden managed storage and uninstall cleanup
type: changed
---

- Reapply the iOS Data Protection floor to existing managed-storage roots and enforce the SQLite protection flag in policy checks.
- Prohibit general pasteboard APIs unless a reviewed local-only, expiring wrapper is introduced.
- Add a scoped, idempotent Mac companion deletion action and document manual login-keychain cleanup after uninstall.
