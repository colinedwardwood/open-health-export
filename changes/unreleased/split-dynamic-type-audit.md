Audit Dynamic Type in its own pass instead of sharing one budget with every
other accessibility check. The combined pass ran long enough on hosted runners
to return "Audit failed to complete in time", and to report Dynamic Type on
controls that pass the identical audit on other shards.
