{
  "version": "1.0.0",
  "status": "in-progress",
  "encoding": ["ndjson", "json", "csv"],
  "fixtures": {
    "tier0.ndjson": {
      "records": 200,
      "seed": 1,
      "sha256": "8313b7a761132295c38557f2e2c56cd2aedc8ecb93b0633d73802977d6751f9c"
    },
    "g1": {
      "role": "R-84/G1 frozen encoder triple: logical-input.json plus expected.ndjson/json/csv",
      "injectedTzDatabase": "fixtures/tz-database-version.txt"
    },
    "ha-ci": {
      "role": "R-89 Home Assistant container config and pinned version window; QA-22 canary pins",
      "currentStable": "2026.8.3",
      "oldestInWindow": "2025.9.4",
      "mosquittoTag": "2.0.22"
    },
    "fix-catalogue.json": {
      "cases": 72,
      "role": "Stage 4 FIX-* meta-test input; every t0 ID has a Linux witness"
    },
    "receiver-sequence.ndjson": {
      "role": "G3/G4 forward-compatibility and convergent-upsert input"
    },
    "receiver-expected-state.json": {
      "role": "G4 expected final state"
    }
  },
  "schema": "schema/ohe.wire.1.json",
  "catalogue": {
    "metrics": "catalogue/metrics.json",
    "hkStatisticsExceptions": "catalogue/hk-statistics-exceptions.json"
  },
  "freeze": {
    "marker": "FROZEN",
    "baselineWhenFrozen": "schema/ohe.wire.1.frozen.json",
    "policy": "B-class changes fail; A-class changes require a MINOR x-ohe-specVersion bump"
  },
  "receiver": "swift run receiver -- spec/v1.0.0/fixtures/receiver-sequence.ndjson",
  "corpusgen": {
    "T0": "swift run corpusgen --tier T0 --seed 1",
    "T1": "swift run corpusgen --tier T1 --seed 1 (10,000,000 records)",
    "T2": "swift run corpusgen --tier T2 --seed 1 (50,000,000 records)",
    "coverage": "at least 60 quantity/category/structural types and 6 source identities",
    "T2Pathologies": ["UUID replay", "tombstone", "retrograde measurement date", "source overlap"]
  },
  "adjacency": "adjacency.json",
  "demo": {
    "field": "demo",
    "when": "true only on synthetic export records",
    "filenamePrefix": "DEMO-"
  }
}
