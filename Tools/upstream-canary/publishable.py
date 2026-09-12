#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""QA-22: Mosquitto latest is the newest Docker Hub tag that `docker pull` can fetch."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request

PLAIN_SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
DOCKERHUB = (
    "https://hub.docker.com/v2/repositories/library/eclipse-mosquitto/tags"
    "?page_size=100&ordering=last_updated"
)


def parse_plain(name: str) -> tuple[int, int, int] | None:
    match = PLAIN_SEMVER.fullmatch(name)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def latest_plain_semver(names: list[str]) -> str:
    parsed = [(parse_plain(name), name) for name in names]
    versions = [(version, name) for version, name in parsed if version is not None]
    if not versions:
        raise SystemExit("no pullable Mosquitto x.y.z Docker Hub tags")
    _, name = max(versions, key=lambda item: item[0])
    return name


def fetch_names(url: str = DOCKERHUB) -> list[str]:
    request = urllib.request.Request(url, headers={"User-Agent": "open-health-exporter-qa"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    return [item["name"] for item in payload.get("results", []) if "name" in item]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("service", choices=["mosquitto"])
    args = parser.parse_args()
    if args.service == "mosquitto":
        print(latest_plain_semver(fetch_names()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
