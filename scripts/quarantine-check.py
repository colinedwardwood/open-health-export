#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""QA-32: every skipped test must cite a quarantine issue and an expiry date."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SKIP_MARKERS = (
    "XCTSkip",
    "XCTSkipIf",
    "XCTSkipUnless",
    "withKnownIssue",
    "@Test(.disabled",
)
ISSUE_RE = re.compile(r"https://github\.com/colinedwardwood/open-health-export/issues/\d+")
EXPIRY_RE = re.compile(r"expires:\s*\d{4}-\d{2}-\d{2}")


def load_policy(root: Path) -> dict:
    policy = json.loads((root / "qa/flake-quarantine.json").read_text())
    if policy.get("schemaVersion") != 1 or policy.get("slaBusinessDays") != 1:
        raise SystemExit("qa/flake-quarantine.json must declare schemaVersion 1 and slaBusinessDays 1")
    return policy


def skip_windows(text: str) -> list[str]:
    windows = []
    for marker in SKIP_MARKERS:
        start = 0
        while True:
            index = text.find(marker, start)
            if index < 0:
                break
            windows.append(text[max(0, index - 240) : index + 240])
            start = index + len(marker)
    return windows


def check_tree(root: Path) -> list[str]:
    problems: list[str] = []
    tests = root / "Tests"
    for path in tests.rglob("*.swift"):
        text = path.read_text()
        relative = path.relative_to(root)
        for window in skip_windows(text):
            if not ISSUE_RE.search(window) or not EXPIRY_RE.search(window):
                problems.append(
                    f"{relative}: skip marker without issue URL and expires: YYYY-MM-DD nearby"
                )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    load_policy(root)
    problems = check_tree(root)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    if args.self_test:
        print("quarantine-check self-test: ok (no unmarked skips)")
    else:
        print("quarantine-check: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
