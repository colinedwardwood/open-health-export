# Demo mode ships as synthetic data, not test machinery

Release builds can load the same seeded corpus as `corpusgen`. Records carry
`demo: true`, files use a `DEMO-` prefix, and sending them to a destination
requires typing that destination's name.
