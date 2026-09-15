#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build fail-closed QA-22 release evidence from canary runs and issues."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def parse_epoch(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def evaluate(runs_payload: dict, issues_payload: list[dict], now: datetime) -> dict:
    completed = [
        run
        for run in runs_payload.get("workflow_runs", [])
        if run.get("event") == "schedule"
        and run.get("status") == "completed"
        and run.get("conclusion") in {"success", "failure"}
    ]
    completed.sort(key=lambda run: run.get("updated_at", ""), reverse=True)
    if not completed:
        return {
            "schemaVersion": 1,
            "acceptable": False,
            "problems": ["no completed scheduled upstream canary run"],
        }

    run = completed[0]
    finished = parse_epoch(run["updated_at"])
    age_hours = max(0.0, (now - finished).total_seconds() / 3600)
    run_url = run.get("html_url", "")
    tracking = [
        issue
        for issue in issues_payload
        if issue.get("state") == "open"
        and issue.get("title", "").startswith("QA-22 canary:")
        and run_url
        and run_url in (issue.get("body") or "")
    ]
    problems: list[str] = []
    if age_hours > 48:
        problems.append(f"latest completed upstream canary is {age_hours:.1f} hours old")
    if run["conclusion"] == "failure" and age_hours > 24 and not tracking:
        problems.append("upstream canary has been red for over 24 hours without its tracking issue")
    return {
        "schemaVersion": 1,
        "acceptable": not problems,
        "problems": problems,
        "run": {
            "id": run.get("id"),
            "conclusion": run["conclusion"],
            "completedAt": run["updated_at"],
            "ageHours": age_hours,
            "url": run_url,
        },
        "trackingIssues": [
            {"number": issue.get("number"), "url": issue.get("html_url")}
            for issue in tracking
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-json", type=Path, required=True)
    parser.add_argument("--issues-json", type=Path, required=True)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--enforce", action="store_true")
    args = parser.parse_args()
    result = evaluate(
        json.loads(args.runs_json.read_text()),
        json.loads(args.issues_json.read_text()),
        datetime.now(timezone.utc),
    )
    args.json_output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if result["acceptable"]:
        print("upstream canary release status: ok")
        return 0
    print("upstream canary release status: " + "; ".join(result["problems"]))
    return 1 if args.enforce else 0


if __name__ == "__main__":
    raise SystemExit(main())
