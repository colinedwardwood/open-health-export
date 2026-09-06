### Portable SQLite module

Storage now imports a repository-owned `CSQLite` system-library shim. It links the platform
SQLite library on Darwin and resolves the runner's `libsqlite3-dev` through pkg-config on Linux,
so the full test suite can compile storage rather than only the dependency-light core targets.
