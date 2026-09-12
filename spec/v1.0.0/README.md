{
  "version": "1.0.0",
  "status": "in-progress",
  "encoding": ["ndjson", "json", "csv"],
  "fixtures": {
    "tier0.ndjson": {
      "records": 200,
      "seed": 1,
      "sha256": "fc8d94a44c31d785078bd06572709f78789ed4cc17877080e1ff081e6baf1b66"
    },
    "g1": {
      "role": "R-84/G1 frozen encoder triple: logical-input.json plus expected.ndjson/json/csv",
      "injectedTzDatabase": "fixtures/tz-database-version.txt",
      "sha256": "833dbb4776d3f05ce6d7f95fa7b0657e3a3d90c13c4f5a9637128814ea505163"
    },
    "ha-ci": {
      "role": "R-89 Home Assistant and R-53 OTLP container pins; QA-22 canary pins",
      "currentStable": "2026.9.2",
      "oldestInWindow": "2025.9.4",
      "mosquittoTag": "2.0.22",
      "otelCollectorTag": "0.160.0"
    },
    "fix-catalogue.json": {
      "cases": 73,
      "role": "Stage 4 FIX-* meta-test input; every t0 ID has a Linux witness"
    },
    "receiver-sequence.ndjson": {
      "role": "G3/G4 forward-compatibility and convergent-upsert input; R-115 serve --seed"
    },
    "receiver-expected-state.json": {
      "role": "G4 expected final state"
    },
    "hk-statistics-reference-vectors.json": {
      "role": "R-80 Linux pipeline vectors for every hkStatistics exception; not Apple capture evidence"
    },
    "t2-tombstone-slice.ndjson": {
      "role": "T2 ExportRun accounting regression: one quantity plus one tombstone"
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
