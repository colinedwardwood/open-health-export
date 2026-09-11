#!/usr/bin/env python3
"""Scan a decrypted iOS backup for synthetic canaries without printing them."""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"backup scan: FAIL: {message}", file=sys.stderr)
    return 1


def contains_any(data: bytes, canaries: list[bytes]) -> bool:
    return any(canary in data for canary in canaries)


def sqlite_text_contains(path: Path, canaries: list[str]) -> bool:
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        for statement in connection.iterdump():
            if any(canary in statement for canary in canaries):
                return True
        connection.close()
    except sqlite3.Error:
        # Raw bytes are still scanned. Non-SQLite files commonly use .db.
        return False
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--canary-file", required=True, type=Path)
    arguments = parser.parse_args()

    root = arguments.root.resolve()
    if not root.is_dir():
        return fail("root is not a directory")

    try:
        canary_text = [
            line.strip()
            for line in arguments.canary_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    except OSError as error:
        return fail(f"cannot read canary file: {error}")
    if len(canary_text) < 3 or len(set(canary_text)) != len(canary_text):
        return fail("provide at least three distinct non-empty canaries")
    if any(len(value.encode("utf-8")) < 16 for value in canary_text):
        return fail("each canary must be at least 16 UTF-8 bytes")

    manifests = list(root.rglob("Manifest.db"))
    if not manifests:
        return fail("Manifest.db is absent; scan a decrypted/extracted backup")

    canaries = [value.encode("utf-8") for value in canary_text]
    files_scanned = 0
    bytes_scanned = 0
    hits: list[str] = []
    errors: list[str] = []

    for directory, _, names in os.walk(root):
        for name in names:
            path = Path(directory, name)
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                errors.append(f"{relative}: symbolic links are not accepted")
                continue
            if contains_any(relative.encode("utf-8"), canaries):
                hits.append(f"path:{relative}")
            try:
                files_scanned += 1
                with path.open("rb") as stream:
                    overlap = b""
                    overlap_size = max(len(canary) for canary in canaries) - 1
                    while chunk := stream.read(1024 * 1024):
                        bytes_scanned += len(chunk)
                        if contains_any(overlap + chunk, canaries):
                            hits.append(f"bytes:{relative}")
                            break
                        overlap = chunk[-overlap_size:]
                if path.name == "Manifest.db" and sqlite_text_contains(path, canary_text):
                    hits.append(f"sqlite:{relative}")
            except OSError as error:
                errors.append(f"{relative}: {error}")

    if errors:
        return fail(f"{len(errors)} unreadable file(s); first: {errors[0]}")
    if hits:
        return fail(f"{len(hits)} canary hit(s); first location: {hits[0]}")

    print(
        "backup scan: PASS: "
        f"{files_scanned} files, {bytes_scanned} bytes, "
        f"{len(manifests)} Manifest.db file(s), zero canary hits"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
