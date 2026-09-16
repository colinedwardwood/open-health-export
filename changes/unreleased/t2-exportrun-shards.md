---
category: fixed
---

Split the fifty-million-record ExportRun memory gate into five contiguous
ten-million-record shards. One GitHub-hosted job gets six hours and the
whole-corpus run needed more, so it was cancelled at the wall every time and the
gate could never go green. Each shard is measured in its own process against the
same 100 MiB ceiling, and release validation requires all five.
