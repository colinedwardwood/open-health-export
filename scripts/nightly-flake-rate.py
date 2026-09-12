#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Compute the QA-32 nightly failure proxy from GitHub workflow conclusions."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path

COUNTED = {"success", "failure"}


def fetch_runs(repository: str, workflow: str, token: str | None) -> dict:
    url = (
        f"https://api.github.com/repos/{repository}/actions/workflows/{workflow}/runs"
        "?event=schedule&status=completed&per_page=100"
    )
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "open-health-exporter-qa",
            "X-GitHub-Api-Version": "2022-11-28",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def calculate(payload: dict, window: int) -> dict:
    runs = [
        run
        for run in payload.get("workflow_runs", [])
        if run.get("event") == "schedule" and run.get("conclusion") in COUNTED
    ][:window]
    failures = sum(run["conclusion"] == "failure" for run in runs)
    rate = 0.0 if not runs else failures * 100.0 / len(runs)
    return {
        "schemaVersion": 1,
        "method": "failed scheduled workflow conclusions / success-or-failure conclusions",
        "windowRequested": window,
        "windowObserved": len(runs),
        "failures": failures,
        "ratePercent": rate,
        "runs": [
            {
                "id": run.get("id"),
                "conclusion": run["conclusion"],
                "createdAt": run.get("created_at"),
                "url": run.get("html_url"),
            }
            for run in runs
        ],
    }


def markdown(result: dict, threshold: float) -> str:
    status = "PASS" if result["ratePercent"] <= threshold else "FAIL"
    lines = [
        "## Nightly flake-rate proxy",
        "",
        f"**{status}: {result['failures']}/{result['windowObserved']} "
        f"({result['ratePercent']:.2f}%)**, release threshold ≤ {threshold:.2f}%.",
        "",
        "This conservative proxy counts failed scheduled workflow conclusions. "
        "Cancelled and skipped runs are excluded; it does not claim to identify "
        "which individual test was flaky.",
        "",
        "| Run | Created | Conclusion |",
        "|---|---|---|",
    ]
    for run in result["runs"]:
        label = f"[{run['id']}]({run['url']})" if run["url"] else str(run["id"])
        lines.append(f"| {label} | {run['createdAt'] or ''} | {run['conclusion']} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--runs-json", type=Path)
    source.add_argument("--repository")
    parser.add_argument("--workflow", default="nightly-volume.yml")
    parser.add_argument("--window", type=int, default=20)
    parser.add_argument("--threshold", type=float, default=1.0)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--enforce", action="store_true")
    args = parser.parse_args()

    payload = (
        json.loads(args.runs_json.read_text())
        if args.runs_json
        else fetch_runs(args.repository, args.workflow, os.environ.get("GH_TOKEN"))
    )
    result = calculate(payload, args.window)
    rendered = markdown(result, args.threshold)
    print(rendered, end="")
    if args.json_output:
        args.json_output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.markdown:
        args.markdown.write_text(rendered)
    if result["windowObserved"] < args.window:
        print(
            f"need {args.window} completed scheduled runs; found {result['windowObserved']}",
            file=sys.stderr,
        )
        return 2 if args.enforce else 0
    if args.enforce and result["ratePercent"] > args.threshold:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
