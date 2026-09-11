Document the three version streams, provenance claims, and licence lock.

`VERSIONING.md` and `spec/compatibility.json` make R-12's independence rule a
stranger-readable file. `PROVENANCE.md` states the R-108 sentence also used in
the README. `dependencies/licences.lock` is generated from Package.swift so a
new runtime identifier cannot land silently (OSS-17).
