---
title: Stream the full T1 corpus through ExportRun
type: changed
---

The nightly volume gate now accounts for all ten million generated T1 records and streams every quantity record through bounded, four-way `ExportRun` pages. It fails on skipped or unknown records, incomplete acknowledgement, or Linux peak RSS above 100 MiB.
