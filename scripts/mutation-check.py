#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""QA-33 mutation check: each committed mutant must make its named test fail."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_catalog(root: Path) -> list[dict]:
    payload = json.loads((root / "qa/mutants.json").read_text())
    mutants = payload.get("mutants")
    if payload.get("schemaVersion") != 1 or not isinstance(mutants, list) or len(mutants) < 3:
        raise SystemExit("qa/mutants.json must declare schemaVersion 1 and at least 3 mutants")
    return mutants


def validate(root: Path, mutants: list[dict]) -> None:
    seen: set[str] = set()
    for mutant in mutants:
        ident = mutant.get("id")
        relative = mutant.get("file")
        needle = mutant.get("find")
        replacement = mutant.get("replace")
        filt = mutant.get("filter")
        if not all(isinstance(value, str) and value for value in (ident, relative, needle, replacement, filt)):
            raise SystemExit(f"mutant {ident!r} is missing required string fields")
        if ident in seen:
            raise SystemExit(f"duplicate mutant id {ident}")
        seen.add(ident)
        if needle == replacement:
            raise SystemExit(f"{ident}: find and replace are identical")
        text = (root / relative).read_text()
        if text.count(needle) != 1:
            raise SystemExit(f"{ident}: find must occur exactly once in {relative}")
        if replacement in text:
            raise SystemExit(f"{ident}: replace already present in {relative}")
        host = mutant.get("host")
        if host is not None and host not in {"darwin", "linux"}:
            raise SystemExit(f"{ident}: host must be darwin or linux")


def host_matches(mutant: dict, platform: str) -> bool:
    host = mutant.get("host")
    if not host:
        return True
    if host == "darwin":
        return platform == "darwin"
    return platform.startswith("linux")


def ran_zero_tests(output: str) -> bool:
    return (
        "Test run with 0 tests" in output
        or "No matching test cases were run" in output
    )


def apply_mutant(path: Path, needle: str, replacement: str) -> str:
    original = path.read_text()
    path.write_text(original.replace(needle, replacement, 1))
    return original


def run_mutant(root: Path, mutant: dict) -> None:
    path = root / mutant["file"]
    original = apply_mutant(path, mutant["find"], mutant["replace"])
    try:
        result = subprocess.run(
            ["swift", "test", "--filter", mutant["filter"]],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            errors="replace",
        )
        output = (result.stdout or "") + (result.stderr or "")
        sys.stdout.write(output)
        if ran_zero_tests(output):
            raise SystemExit(
                f"mutant {mutant['id']} filter {mutant['filter']} matched zero tests"
            )
        if result.returncode == 0:
            raise SystemExit(
                f"mutant {mutant['id']} survived {mutant['filter']}: the named test still passed"
            )
        print(f"mutant {mutant['id']} killed by {mutant['filter']} (exit {result.returncode})")
    finally:
        path.write_text(original)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--id")
    args = parser.parse_args()
    root = args.root.resolve()
    mutants = load_catalog(root)
    validate(root, mutants)
    if args.self_test:
        print(f"mutation-check self-test: ok mutants={len(mutants)}")
        return 0
    selected = [item for item in mutants if args.id is None or item["id"] == args.id]
    if not selected:
        raise SystemExit(f"no mutant named {args.id}")
    ran = 0
    for mutant in selected:
        if not host_matches(mutant, sys.platform):
            print(f"mutant {mutant['id']} skipped on {sys.platform}")
            continue
        run_mutant(root, mutant)
        ran += 1
    if ran == 0:
        raise SystemExit("no mutants apply on this host")
    return 0


if __name__ == "__main__":
    sys.exit(main())
