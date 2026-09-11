SEC-30: exclude the app's storage root from iCloud and Finder backups. A Data
Protection class is inherited by new files in a directory but backup exclusion
is not, so the state database, journal and queued payloads were being swept
into backups and could be restored onto a device that was never authorised to
read that Health data (T-16). Policycheck asserts the exclusion at the point
the directory is created, and the test asserts the flag reads back rather than
trusting that the call succeeded.

R-62: the per-feature authorisation check is now a repo-wide policycheck gate
instead of a string scan of one file, since a new call site elsewhere is how
this would actually regress.
