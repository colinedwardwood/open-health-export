# Open Health Exporter reference receiver

This is not a medical device. It does not diagnose or treat anything.

The receiver is the executable form of `ohe.wire/1`. It upserts by UUID, applies
tombstones, and ignores unknown kinds. G3/G4 fixtures live under
`spec/v1.0.0/fixtures/`.

## One command (R-115)

From this directory:

```
docker compose up --build
```

That starts:

1. this receiver, seeded with `receiver-sequence.ndjson`
2. Prometheus scraping `/metrics`
3. Grafana on http://127.0.0.1:3000 with the Classic dashboard pre-provisioned
   (anonymous viewer; lab use on loopback)

You should see ingested-line and live-quantity panels populated from the seed
fixture (one live heart-rate sample after the step-count tombstone). POST more
NDJSON to `http://127.0.0.1:8080/ingest`.

Without Docker:

```
swift run receiver serve --port 8080 --seed spec/v1.0.0/fixtures/receiver-sequence.ndjson
```

File mode (conformance state only):

```
swift run receiver -- spec/v1.0.0/fixtures/receiver-sequence.ndjson
```

The dashboard JSON is CC0-1.0. Receiver code is AGPL-3.0-or-later like the rest
of the tree. Grafana community-catalogue upload is not done here; it needs an
org Grafana Cloud account.
