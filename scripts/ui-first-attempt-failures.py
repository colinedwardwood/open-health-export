#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: FSL-1.1-ALv2
"""#74: report UI test cases whose first attempt failed, even when a retry passed.

`xcodebuild -retry-tests-on-failure` turns an intermittent product bug into a green
job. This reads the xcresult bundle, counts every case whose first attempt failed,
prints them to the job summary, and fails unless each is listed under
`quarantinedUITests` in qa/flake-quarantine.json.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_tests(xcresult: Path) -> dict:
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(xcresult)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(output)


def first_attempt_failures(tree: dict) -> tuple[int, list[dict]]:
    """Return (cases seen, cases whose first attempt failed).

    A case that was retried carries one `Repetition` child per attempt, in order. A case
    that ran once has none, and its own result is its first attempt.
    """
    cases = 0
    failures: list[dict] = []

    def walk(node: dict) -> None:
        nonlocal cases
        children = node.get("children", [])
        if node.get("nodeType") == "Test Case":
            cases += 1
            repetitions = [c for c in children if c.get("nodeType") == "Repetition"]
            first = repetitions[0] if repetitions else node
            if first.get("result") == "Failed":
                failures.append(
                    {
                        "id": node.get("nodeIdentifier") or node.get("name", "?"),
                        "attempts": max(len(repetitions), 1),
                        "finalResult": node.get("result", "Unknown"),
                    }
                )
            return
        for child in children:
            walk(child)

    for root in tree.get("testNodes", []):
        walk(root)
    return cases, failures


def is_quarantined(identifier: str, quarantined: list[str]) -> bool:
    return any(identifier == q or identifier.endswith("/" + q) or identifier.endswith(q + "()") for q in quarantined)


def report(cases: int, failures: list[dict], quarantined: list[str]) -> tuple[str, int]:
    unlisted = [f for f in failures if not is_quarantined(f["id"], quarantined)]
    lines = [
        "### UI first-attempt results",
        "",
        f"Cases: {cases}. First-attempt failures: {len(failures)}. Not in quarantine: {len(unlisted)}.",
    ]
    if failures:
        lines += ["", "| Case | Attempts | Final | Quarantined |", "| --- | --- | --- | --- |"]
        for f in failures:
            listed = "yes" if is_quarantined(f["id"], quarantined) else "no"
            lines.append(f"| `{f['id']}` | {f['attempts']} | {f['finalResult']} | {listed} |")
    return "\n".join(lines) + "\n", 1 if unlisted else 0


def self_test() -> None:
    def case(name: str, result: str, runs: list[str] | None = None) -> dict:
        children = [{"nodeType": "Repetition", "name": f"Run {i + 1}", "result": r} for i, r in enumerate(runs or [])]
        return {"nodeType": "Test Case", "name": name, "nodeIdentifier": f"Suite/{name}", "result": result, "children": children}

    tree = {
        "testNodes": [
            {
                "nodeType": "Test Plan",
                "children": [
                    {
                        "nodeType": "Test Suite",
                        "name": "Suite",
                        "children": [
                            case("passes()", "Passed"),
                            case("flaky()", "Passed", ["Failed", "Passed"]),
                            case("broken()", "Failed", ["Failed", "Failed"]),
                            case("steady()", "Passed", ["Passed"]),
                        ],
                    }
                ],
            }
        ]
    }
    cases, failures = first_attempt_failures(tree)
    assert cases == 4, cases
    assert [f["id"] for f in failures] == ["Suite/flaky()", "Suite/broken()"], failures
    assert report(cases, failures, [])[1] == 1
    assert report(cases, failures, ["Suite/flaky()"])[1] == 1
    assert report(cases, failures, ["Suite/flaky()", "broken()"])[1] == 0
    assert report(4, [], [])[1] == 0
    print("ui-first-attempt-failures self-test: ok")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("xcresult", type=Path, nargs="?")
    parser.add_argument("--quarantine", type=Path, default=Path("qa/flake-quarantine.json"))
    parser.add_argument("--summary", type=Path, help="file to append the markdown report to")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.xcresult is None:
        parser.error("xcresult is required")
    if not args.xcresult.exists():
        # The test step failed before it wrote a bundle, and that step already fails the job.
        print(f"No result bundle at {args.xcresult}; nothing to audit.", file=sys.stderr)
        return 0
    quarantined = json.loads(args.quarantine.read_text()).get("quarantinedUITests", [])
    cases, failures = first_attempt_failures(load_tests(args.xcresult))
    text, code = report(cases, failures, quarantined)
    print(text)
    if args.summary:
        with args.summary.open("a") as handle:
            handle.write(text)
    if code:
        print("First-attempt UI failure outside qa/flake-quarantine.json: fix it or quarantine it.", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
