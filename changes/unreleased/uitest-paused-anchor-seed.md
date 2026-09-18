UI tests that seed a paused-type banner apply the hold in memory on appear
so Status shows it before SQLite seeding finishes. A later SQLite gap refresh
does not replace that seed with an empty load. Reset still clears holds on
launches that are not seeding one.
