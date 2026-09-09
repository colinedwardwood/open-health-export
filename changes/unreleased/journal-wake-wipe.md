### Richer journal, wake attribution, and store wipe

Journal rows now record the run trigger and sample tallies (R-20). `WakeLedger`
appends before work; `WakeAttribution` classifies overdue windows as scheduling
versus execution (R-22). `StateStore.wipe` clears every table and unlinks pending
payload files after COMMIT (R-43). The process-exit matrix now reopens SQLite,
replays as needed, relaunches the export, and asserts that a successful derived
outcome remains readable from the journal at every fault boundary.
