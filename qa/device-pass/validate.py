#!/usr/bin/env python3
"""Validate the locally recorded, value-free R-87 device-pass result."""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime
from pathlib import Path

CHECKS = {
    "onboarding-disclosure",
    "authorization-states",
    "health-browser-comparison",
    "destination-canary",
    "destination-change-notice",
    "certificate-change-halt",
    "diagnostic-second-person",
    "hidden-destination-prohibited",
    "statistics-comparison",
    "encrypted-backup",
    "delete-all",
    "status-widget",
    "voiceover-critical-flows",
}
OUTCOMES = {"pass", "fail", "blocked"}
CHARACTERISTICS = {"phone", "watch", "third-party", "clinical", "manual-entry", "other"}


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} RESULT.json", file=sys.stderr)
        return 2
    try:
        record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"device pass: INVALID: {error}", file=sys.stderr)
        return 1

    errors: list[str] = []
    require(record.get("schemaVersion") == 1, "schemaVersion must be 1", errors)
    try:
        uuid.UUID(record.get("runId", ""))
    except (ValueError, TypeError):
        errors.append("runId must be a UUID")
    require(bool(record.get("releaseCandidate")), "releaseCandidate is required", errors)

    device = record.get("device", {})
    for field in ("model", "osBuild", "appBuild"):
        require(bool(device.get(field)), f"device.{field} is required", errors)

    store = record.get("store", {})
    require(isinstance(store.get("historyDays"), int) and store.get("historyDays", 0) >= 730,
            "store.historyDays must be at least 730", errors)
    require(isinstance(store.get("sourceCount"), int) and store.get("sourceCount", 0) >= 3,
            "store.sourceCount must be at least 3", errors)
    characteristics = store.get("characteristics", [])
    require(bool(characteristics) and set(characteristics) <= CHARACTERISTICS,
            "store.characteristics contains an invalid or empty value", errors)

    raw_checks = record.get("checks", [])
    require(isinstance(raw_checks, list), "checks must be an array", errors)
    checks = raw_checks if isinstance(raw_checks, list) else []
    ids = [check.get("id") for check in checks if isinstance(check, dict)]
    require(len(ids) == len(checks), "every check must be an object", errors)
    require(len(ids) == len(set(ids)), "check IDs must be unique", errors)
    require(set(ids) == CHECKS, "checks must contain exactly the protocol check IDs", errors)
    for check in checks:
        if not isinstance(check, dict):
            continue
        require(check.get("outcome") in OUTCOMES, f"{check.get('id')}: invalid outcome", errors)
        require(bool(check.get("evidenceRef")), f"{check.get('id')}: evidenceRef is required", errors)
        require(isinstance(check.get("note"), str), f"{check.get('id')}: note must be a string", errors)

    signoff = record.get("signoff", {})
    for field in ("operator", "reviewer", "completedAt"):
        require(bool(signoff.get(field)), f"signoff.{field} is required", errors)
    try:
        datetime.fromisoformat(str(signoff.get("completedAt", "")).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        errors.append("signoff.completedAt must be ISO 8601")
    expected = "pass" if checks and all(c.get("outcome") == "pass" for c in checks) else "fail"
    require(signoff.get("outcome") == expected, f"signoff.outcome must be {expected}", errors)

    if errors:
        print("device pass: INVALID\n- " + "\n- ".join(errors), file=sys.stderr)
        return 1
    print(f"device pass: VALID STRUCTURE; recorded outcome={expected}; physical execution not attested")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
