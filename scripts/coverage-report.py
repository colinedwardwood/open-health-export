#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Publish LLVM coverage by Swift module and enforce focused QA-33 gates."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def load_coverage(path: Path) -> list[dict]:
    payload = json.loads(path.read_text())
    return [item for datum in payload.get("data", []) for item in datum.get("files", [])]


def source_module(filename: str) -> str | None:
    match = re.search(r"(?:^|/)Sources/([^/]+)/", filename)
    return match.group(1) if match else None


def module_totals(files: list[dict]) -> dict[str, tuple[int, int]]:
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for item in files:
        module = source_module(item.get("filename", ""))
        if not module:
            continue
        lines = item.get("summary", {}).get("lines", {})
        totals[module][0] += int(lines.get("covered", 0))
        totals[module][1] += int(lines.get("count", 0))
    return {name: (values[0], values[1]) for name, values in totals.items()}


def executable_lines(files: list[dict]) -> dict[str, dict[int, bool]]:
    result: dict[str, dict[int, bool]] = {}
    for item in files:
        filename = item.get("filename", "")
        marker = "/Sources/"
        if marker not in filename:
            continue
        relative = "Sources/" + filename.split(marker, 1)[1]
        lines: dict[int, bool] = {}
        for segment in item.get("segments", []):
            if len(segment) >= 4 and segment[3]:
                line, count = int(segment[0]), int(segment[2])
                lines[line] = lines.get(line, False) or count > 0
        result[relative] = lines
    return result


def changed_lines(base: str, head: str) -> dict[str, set[int]]:
    command = ["git", "diff", "--unified=0", f"{base}...{head}", "--", "Sources"]
    diff = subprocess.run(command, check=True, text=True, capture_output=True).stdout
    changed: dict[str, set[int]] = defaultdict(set)
    current: str | None = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
        elif current and line.startswith("@@"):
            match = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if match:
                start, count = int(match.group(1)), int(match.group(2) or "1")
                changed[current].update(range(start, start + count))
    return changed


def percent(covered: int, count: int) -> float:
    return 100.0 if count == 0 else covered * 100.0 / count


def report(
    files: list[dict], policy: dict, base: str | None, head: str
) -> tuple[str, dict, list[str]]:
    totals = module_totals(files)
    failures: list[str] = []
    rows = ["| Module | Lines | Coverage | Gate |", "|---|---:|---:|---:|"]
    critical = policy["criticalModules"]
    for module in sorted(totals):
        covered, count = totals[module]
        observed = percent(covered, count)
        gate = critical.get(module)
        rows.append(
            f"| {module} | {covered}/{count} | {observed:.2f}% | "
            + (f"{gate:.2f}%" if gate is not None else "publish only")
            + " |"
        )
        if gate is not None and observed + 1e-9 < float(gate):
            failures.append(f"{module}: {observed:.2f}% is below {gate:.2f}%")
    for missing in sorted(set(critical) - set(totals)):
        failures.append(f"{missing}: no coverage data")

    result: dict = {
        "schemaVersion": 1,
        "modules": {
            name: {"covered": value[0], "count": value[1], "percent": percent(*value)}
            for name, value in sorted(totals.items())
        },
    }
    if base:
        executable = executable_lines(files)
        changed = changed_lines(base, head)
        relevant = [
            executable[path][line]
            for path, lines in changed.items()
            for line in sorted(lines)
            if path in executable and line in executable[path]
        ]
        covered = sum(relevant)
        observed = percent(covered, len(relevant))
        minimum = float(policy["patchLineMinimum"])
        result["patch"] = {
            "covered": covered,
            "count": len(relevant),
            "percent": observed,
            "base": base,
            "head": head,
        }
        rows.extend(["", f"Patch coverage: **{covered}/{len(relevant)} ({observed:.2f}%)**."])
        if observed + 1e-9 < minimum:
            failures.append(f"patch: {observed:.2f}% is below {minimum:.2f}%")
    transition = policy.get("transitionCoverage", {})
    evidence = transition.get("evidence")
    rows.extend(
        [
            "",
            "Transition gate: "
            f"**{float(transition.get('minimum', 100)):.0f}%**; "
            + (f"asserted by `{evidence}`." if evidence else "automated evidence is not yet configured."),
        ]
    )
    return "\n".join(rows) + "\n", result, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--policy", type=Path, default=Path("qa/coverage-policy.json"))
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--no-enforce", action="store_true")
    args = parser.parse_args()

    markdown, result, failures = report(
        load_coverage(args.coverage),
        json.loads(args.policy.read_text()),
        args.base,
        args.head,
    )
    print(markdown, end="")
    if args.markdown:
        args.markdown.write_text(markdown)
    if args.json_output:
        args.json_output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if failures and not args.no_enforce:
        print("coverage gates failed:\n- " + "\n- ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
