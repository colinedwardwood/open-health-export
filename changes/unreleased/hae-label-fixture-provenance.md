Label HAE sidecars as a compatibility export, and require fixture provenance.

R-12 keeps Health Auto Export ineligible for freshness and monitoring; the in-app
label and README now say so. Frozen NDJSON cannot grow a synthetic header without
breaking G1, so QA-09 accepts a sibling provenance file.
