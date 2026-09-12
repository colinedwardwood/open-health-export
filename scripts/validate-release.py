#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fail closed unless repository, issue, checks, and nightly evidence permit release."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def issue_sections(body: str) -> dict[str, str]:
    matches = list(re.finditer(r"^### (.+?)\s*$", body, re.MULTILINE))
    return {
        match.group(1): body[match.end() : matches[index + 1].start() if index + 1 < len(matches) else None].strip()
        for index, match in enumerate(matches)
    }


def check_repository(readme: str, policy: dict) -> list[str]:
    problems: list[str] = []
    status = re.search(r"<!--\s*maintenance-status:\s*([a-z-]+)\s*-->", readme)
    if not status or status.group(1) not in policy["maintenanceStatuses"]:
        problems.append("README maintenance-status marker is missing or invalid")
    for platform, minimum in policy["requiredMatrix"].items():
        row = re.search(
            rf"^\|\s*{re.escape(platform)}\s*\|\s*([^|]+?)\s*\|",
            readme,
            re.MULTILINE,
        )
        if not row or minimum not in row.group(1):
            problems.append(f"README supported-OS matrix lacks {platform} {minimum}")
    return problems


def check_issue(body: str, policy: dict, tag: str | None) -> list[str]:
    problems: list[str] = []
    sections = issue_sections(body)
    for heading in policy["requiredIssueSections"]:
        value = sections.get(heading, "")
        if not value or value.lower() in {"_no response_", "n/a", "none"}:
            problems.append(f"release issue section is empty: {heading}")
    unchecked = re.findall(r"^- \[ \] (.+)$", body, re.MULTILINE)
    if unchecked:
        problems.append(f"release issue has {len(unchecked)} unchecked gate(s)")
    checked = re.findall(r"^- \[[xX]\] ", body, re.MULTILINE)
    if not checked:
        problems.append("release issue contains no completed checklist gates")
    if tag:
        version = sections.get("App version", "").strip()
        if version != tag:
            problems.append(f"release tag {tag!r} does not match issue app version {version!r}")
    return problems


def check_runs(payload: dict, required: list[str]) -> list[str]:
    runs = payload.get("check_runs", payload if isinstance(payload, list) else [])
    successful = {
        run.get("name", "")
        for run in runs
        if run.get("status") == "completed" and run.get("conclusion") == "success"
    }
    return [
        f"required check is not successful: {name}"
        for name in required
        if not any(observed == name or observed.startswith(name + " ") or observed.startswith(name + " (") for observed in successful)
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--readme", type=Path, default=Path("README.md"))
    parser.add_argument("--policy", type=Path, default=Path("qa/release-gate.json"))
    parser.add_argument("--issue-body", type=Path, required=True)
    parser.add_argument("--checks", type=Path, required=True)
    parser.add_argument("--flake-report", type=Path, required=True)
    parser.add_argument("--tag")
    args = parser.parse_args()

    policy = json.loads(args.policy.read_text())
    problems = check_repository(args.readme.read_text(), policy)
    problems += check_issue(args.issue_body.read_text(), policy, args.tag)
    problems += check_runs(json.loads(args.checks.read_text()), policy["requiredChecks"])
    flake = json.loads(args.flake_report.read_text())
    if flake.get("windowObserved", 0) < policy["flakeWindow"]:
        problems.append(
            f"nightly evidence has {flake.get('windowObserved', 0)} runs; "
            f"{policy['flakeWindow']} required"
        )
    if float(flake.get("ratePercent", 100.0)) > policy["flakeRateMaximum"]:
        problems.append(
            f"nightly flake proxy {flake.get('ratePercent')}% exceeds "
            f"{policy['flakeRateMaximum']}%"
        )
    if problems:
        print("release refused:\n- " + "\n- ".join(problems), file=sys.stderr)
        return 1
    print("release evidence: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
