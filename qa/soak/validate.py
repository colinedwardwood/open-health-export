#!/usr/bin/env python3
"""Validate R-88 diary continuity and reconciliation gate semantics."""

from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

EVENTS = {"none", "restart", "os-update", "app-update", "offline", "queue-gap", "other"}
CLASSES = {
    "healthkit-no-callback-deletion",
    "r71-platform-cap",
    "queue-eviction-with-gap",
    "hae-profile-limitation",
}
PROFILES = {"local-file", "https", "mqtt", "companion", "hae"}


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: top level must be an object")
    return value


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def parse_date(value: object, field: str, errors: list[str]) -> date | None:
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        errors.append(f"{field} must be an ISO date")
        return None


def valid_datetime(value: object) -> bool:
    try:
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return True
    except (TypeError, ValueError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--diary", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        diary, result = read_json(arguments.diary), read_json(arguments.result)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"soak: INVALID: {error}", file=sys.stderr)
        return 1

    errors: list[str] = []
    require(diary.get("schemaVersion") == 1, "diary.schemaVersion must be 1", errors)
    require(result.get("schemaVersion") == 1, "result.schemaVersion must be 1", errors)
    try:
        diary_id = uuid.UUID(diary.get("runId", ""))
        result_id = uuid.UUID(result.get("runId", ""))
        require(diary_id == result_id, "runId must match across files", errors)
    except (ValueError, TypeError):
        errors.append("both runId values must be UUIDs")

    device = diary.get("device", {})
    for field in ("model", "osBuild", "appBuild"):
        require(bool(device.get(field)), f"device.{field} is required", errors)
    profile = diary.get("destinationProfile")
    require(profile in PROFILES, "destinationProfile is invalid", errors)

    entries = diary.get("entries", [])
    require(isinstance(entries, list) and len(entries) >= 21, "at least 21 diary entries are required", errors)
    entries = entries if isinstance(entries, list) else []
    dates: list[date] = []
    for index, entry in enumerate(entries if isinstance(entries, list) else []):
        parsed = parse_date(entry.get("date"), f"entries[{index}].date", errors)
        if parsed:
            dates.append(parsed)
        require(valid_datetime(entry.get("recordedAt")), f"entries[{index}].recordedAt is invalid", errors)
        require(entry.get("installed") is True, f"entries[{index}]: installed must remain true", errors)
        require(entry.get("destinationConfigured") is True,
                f"entries[{index}]: destinationConfigured must remain true", errors)
        require(isinstance(entry.get("successfulCheckVisible"), bool),
                f"entries[{index}].successfulCheckVisible must be boolean", errors)
        events = entry.get("events", [])
        require(isinstance(events, list) and bool(events) and set(events) <= EVENTS,
                f"entries[{index}].events is invalid or empty", errors)
        require(not ("none" in events and len(events) > 1),
                f"entries[{index}]: none cannot accompany another event", errors)
        require(bool(entry.get("evidenceRef")), f"entries[{index}].evidenceRef is required", errors)
        require(isinstance(entry.get("note"), str), f"entries[{index}].note must be a string", errors)
    if len(dates) == len(entries):
        require(len(dates) == len(set(dates)), "diary dates must be unique", errors)
        require(all(b - a == timedelta(days=1) for a, b in zip(dates, dates[1:])),
                "diary dates must be ordered and consecutive", errors)

    window = result.get("window", {})
    start = parse_date(window.get("startDate"), "window.startDate", errors)
    end = parse_date(window.get("endDate"), "window.endDate", errors)
    if dates and start and end:
        require(start == dates[0] and end == dates[-1], "result window must match diary endpoints", errors)
        require((end - start).days + 1 >= 21, "result window must cover at least 21 days", errors)

    reconciliation = result.get("reconciliation", {})
    require(reconciliation.get("completed") is True, "reconciliation.completed must be true", errors)
    require(isinstance(reconciliation.get("cellsCompared"), int)
            and reconciliation.get("cellsCompared", 0) > 0,
            "reconciliation.cellsCompared must be positive", errors)
    raw_discrepancies = reconciliation.get("discrepancies", [])
    require(isinstance(raw_discrepancies, list), "reconciliation.discrepancies must be an array", errors)
    discrepancies = raw_discrepancies if isinstance(raw_discrepancies, list) else []
    seen_classes: set[str] = set()
    for index, item in enumerate(discrepancies if isinstance(discrepancies, list) else []):
        kind = item.get("class")
        require(kind in CLASSES, f"discrepancies[{index}].class is invalid", errors)
        require(kind not in seen_classes, f"duplicate discrepancy class {kind}", errors)
        seen_classes.add(kind)
        require(isinstance(item.get("count"), int) and item.get("count", 0) > 0,
                f"discrepancies[{index}].count must be positive", errors)
        require(bool(item.get("issueRef")), f"discrepancies[{index}].issueRef is required", errors)
    if "hae-profile-limitation" in seen_classes:
        require(profile == "hae", "HAE explanation is valid only for an HAE profile", errors)
    unexplained = reconciliation.get("unexplained")
    require(isinstance(unexplained, int) and unexplained >= 0,
            "reconciliation.unexplained must be nonnegative", errors)
    require(bool(re.fullmatch(r"sha256:[0-9a-f]{64}", reconciliation.get("evidenceDigest", ""))),
            "reconciliation.evidenceDigest must be sha256:<64 lowercase hex>", errors)

    signoff = result.get("signoff", {})
    for field in ("operator", "reviewer"):
        require(bool(signoff.get(field)), f"signoff.{field} is required", errors)
    require(valid_datetime(signoff.get("completedAt")), "signoff.completedAt is invalid", errors)
    expected = "pass" if not errors and unexplained == 0 else "fail"
    require(signoff.get("outcome") == expected, f"signoff.outcome must be {expected}", errors)

    if errors:
        print("soak: INVALID\n- " + "\n- ".join(errors), file=sys.stderr)
        return 1
    print(
        "soak: VALID STRUCTURE; "
        f"days={len(entries)}; explainedClasses={len(discrepancies)}; "
        f"unexplained={unexplained}; recorded outcome={expected}; physical execution not attested"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
