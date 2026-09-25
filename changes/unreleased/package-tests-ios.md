CI runs the package test suites on an iOS simulator as well as macOS and Linux, so
code that only exists on iOS is compiled and tested; with the old HTTP transport
this run fails on the launch-crash exception. Keychain failures now keep their
status instead of reading as a missing credential, and every keychain query uses
the Data Protection keychain the item was written to (#38, part of #62).
