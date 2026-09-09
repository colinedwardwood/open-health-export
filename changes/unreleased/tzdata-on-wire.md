Live batch headers carry the declared `tzDatabaseVersion` when the host
tzdata identity is known. Frozen G1 fixtures omit the field. The iOS
harness records `TimeZone.timeZoneDataVersion` instead of the placeholder
`host`.
