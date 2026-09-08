{
  "version": "1.0.0",
  "status": "in-progress",
  "encoding": ["ndjson", "json", "csv"],
  "fixtures": {
    "tier0.ndjson": {
      "records": 200,
      "seed": 1,
      "sha256": "e88430b1e69a5505a9db085ffe710fb372e170a13bb37e09c496511734972009"
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
  "catalogue": "catalogue/metrics.json",
  "freeze": {
    "marker": "FROZEN",
    "baselineWhenFrozen": "schema/ohe.wire.1.frozen.json",
    "policy": "B-class changes fail; A-class changes require a MINOR x-ohe-specVersion bump"
  },
  "receiver": "swift run receiver -- spec/v1.0.0/fixtures/receiver-sequence.ndjson",
  "adjacency": "adjacency.json",
  "demo": {
    "field": "demo",
    "when": "true only on synthetic export records",
    "filenamePrefix": "DEMO-"
  }
}
