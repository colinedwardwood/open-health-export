{
  "version": "1.0.0",
  "status": "in-progress",
  "encoding": ["ndjson", "json", "csv"],
  "fixtures": {
    "tier0.ndjson": {
      "records": 200,
      "seed": 1,
      "sha256": "6dda54d56568609d4505e33cc5bc5337032a9cd80e4f331b4512424257b59728"
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
