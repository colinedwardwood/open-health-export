# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


coverage = load("coverage_report", "coverage-report.py")
flakes = load("nightly_flake_rate", "nightly-flake-rate.py")
release = load("validate_release", "validate-release.py")


class CoverageTests(unittest.TestCase):
    def test_aggregates_modules_without_global_gate(self):
        files = [
            {
                "filename": "/repo/Sources/CoreDomain/Domain.swift",
                "summary": {"lines": {"covered": 9, "count": 10}},
            },
            {
                "filename": "/repo/Tests/CoreTests.swift",
                "summary": {"lines": {"covered": 100, "count": 100}},
            },
        ]
        self.assertEqual(coverage.module_totals(files), {"CoreDomain": (9, 10)})

    def test_critical_threshold_fails(self):
        files = [
            {
                "filename": "/repo/Sources/CoreDomain/Domain.swift",
                "summary": {"lines": {"covered": 8, "count": 10}},
            }
        ]
        _, _, failures = coverage.report(
            files,
            {
                "criticalModules": {"CoreDomain": 90.0},
                "patchLineMinimum": 80.0,
                "transitionCoverage": {},
            },
            None,
            "HEAD",
        )
        self.assertIn("CoreDomain: 80.00% is below 90.00%", failures)


class FlakeTests(unittest.TestCase):
    def test_excludes_cancelled_and_non_scheduled_runs(self):
        payload = {
            "workflow_runs": [
                {"id": 1, "event": "schedule", "conclusion": "failure"},
                {"id": 2, "event": "schedule", "conclusion": "success"},
                {"id": 3, "event": "schedule", "conclusion": "cancelled"},
                {"id": 4, "event": "workflow_dispatch", "conclusion": "failure"},
            ]
        }
        result = flakes.calculate(payload, 20)
        self.assertEqual(result["windowObserved"], 2)
        self.assertEqual(result["ratePercent"], 50.0)


class ReleaseTests(unittest.TestCase):
    def test_repository_requires_machine_readable_status_and_matrix(self):
        policy = {
            "maintenanceStatuses": ["maintained"],
            "requiredMatrix": {"iOS": "18.0"},
        }
        readme = "<!-- maintenance-status: maintained -->\n| iOS | 18.0 | supported |\n"
        self.assertEqual(release.check_repository(readme, policy), [])

    def test_unchecked_issue_gate_is_rejected(self):
        body = "### App version\n\nv1.0.0\n\n- [ ] Device pass\n"
        policy = {"requiredIssueSections": ["App version"]}
        self.assertIn(
            "release issue has 1 unchecked gate(s)",
            release.check_issue(body, policy, "v1.0.0"),
        )

    def test_all_required_checks_must_succeed(self):
        payload = {
            "check_runs": [
                {"name": "export-core", "status": "completed", "conclusion": "failure"}
            ]
        }
        self.assertEqual(
            release.check_runs(payload, ["export-core"]),
            ["required check is not successful: export-core"],
        )


if __name__ == "__main__":
    unittest.main()
