UI tests that seed a paused-type banner apply the hold in memory on appear
so Status shows it before SQLite seeding finishes. Reset still clears holds
on launches that are not seeding one.
