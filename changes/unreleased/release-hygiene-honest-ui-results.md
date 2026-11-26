Release builds no longer contain the network-path, iPad-notice and HealthKit-availability
test overrides, and compile with zero warnings. CI now fails on any Release warning or
test-hook string in a shipped binary, and reports UI test cases that only passed on retry.
