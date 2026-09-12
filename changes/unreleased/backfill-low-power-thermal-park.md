Backfill now parks before the next HealthKit day when Low Power Mode is on
or thermal state is serious or critical, so a deferred chunk is not marked
complete. The job resumes from the same checkpoint once the device recovers.
