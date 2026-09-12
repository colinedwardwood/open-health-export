#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAPPING = ROOT / "qa/nfr-mapping.json"
TUPLE_FIELDS = {"workload", "device", "os", "metric", "threshold", "percentile"}
REQUIRED_IDS = {f"R-{number}" for number in range(70, 80)}


def require_path(relative: str, context: str) -> None:
    path = ROOT / relative.split("#", 1)[0]
    if not path.exists():
        raise ValueError(f"{context} references missing path {relative}")


def validate_tuple(value: object, context: str) -> None:
    if not isinstance(value, dict) or set(value) != TUPLE_FIELDS:
        raise ValueError(f"{context} must contain exactly {sorted(TUPLE_FIELDS)}")
    if any(item is None or str(item).strip() == "" for item in value.values()):
        raise ValueError(f"{context} contains an empty six-tuple value")


def validate() -> None:
    document = json.loads(MAPPING.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1:
        raise ValueError("schemaVersion must be 1")
    if document.get("overallStatus") != "mapped-pending-device-measurement":
        raise ValueError("overallStatus must remain honest about pending device evidence")
    gate = document.get("regressionGate", {})
    if gate.get("failureThresholdPercent") != 20:
        raise ValueError("automated regression threshold must be 20 percent")
    require_path(gate.get("runner", ""), "regressionGate")
    require_path(gate.get("comparator", ""), "regressionGate")

    entries = document.get("entries")
    if not isinstance(entries, list):
        raise ValueError("entries must be an array")
    ids = [entry.get("id") for entry in entries]
    if set(ids) != REQUIRED_IDS or len(ids) != len(REQUIRED_IDS):
        raise ValueError(f"entries must map exactly {sorted(REQUIRED_IDS)}")

    regression_proxies = 0
    for entry in entries:
        identifier = entry["id"]
        validate_tuple(entry.get("sixTuple"), f"{identifier}.sixTuple")
        if entry.get("verificationKind") != "physical-protocol":
            raise ValueError(f"{identifier} device acceptance must remain a physical protocol")
        if entry.get("status") != "pending-measurement":
            raise ValueError(f"{identifier} must remain pending until recorded evidence exists")
        if entry.get("satisfiesAcceptance") is not False:
            raise ValueError(f"{identifier} must not claim device acceptance")
        require_path(entry.get("evidence", ""), identifier)

        proxy = entry.get("automatedProxy")
        if proxy is None:
            continue
        validate_tuple(proxy.get("sixTuple"), f"{identifier}.automatedProxy.sixTuple")
        if proxy.get("satisfiesAcceptance") is not False:
            raise ValueError(f"{identifier} proxy must not claim device acceptance")
        require_path(proxy.get("runner", ""), f"{identifier}.automatedProxy")
        if workflow := proxy.get("workflow"):
            require_path(workflow, f"{identifier}.automatedProxy")
        if baseline := proxy.get("baseline"):
            require_path(baseline, f"{identifier}.automatedProxy")
        if proxy.get("kind") == "automated-regression":
            regression_proxies += 1

    if regression_proxies == 0:
        raise ValueError("at least one automated proxy must exercise the >20% regression gate")


if __name__ == "__main__":
    try:
        validate()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"NFR mapping invalid: {error}", file=sys.stderr)
        raise SystemExit(1)
    print("NFR mapping: ok (R-70...R-79; device evidence pending)")
