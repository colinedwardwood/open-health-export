### Richer journal, wake attribution, and store wipe

Journal rows now record the run trigger and sample tallies (R-20). `WakeLedger`
appends before work; `WakeAttribution` classifies overdue windows as scheduling
versus execution (R-22). `StateStore.wipe` clears every table and unlinks pending
payload files after COMMIT (R-43). Revocation purge is still missing.
