Every closed R-21 outcome is now derived from a tally, including
`local_network_denied`. A destination that accepts the connection and silently
discards the body cannot become `success`. `ExportRun` maps classified
`DestinationSendError` values onto the closed outcome set instead of letting
the transport throw past the journal, and a 10,000-tuple check refuses success
whenever fewer records were acknowledged than read.
