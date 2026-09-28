The security-advisory fetch now lives in a tested `AdvisoryService` in a new
`AppServices` package module, with its saved state behind a storage protocol; the
view asks the service what to show (#42, part 2).
