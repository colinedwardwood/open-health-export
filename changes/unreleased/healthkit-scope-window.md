SEC-16: thread each destination's start-inclusive/end-exclusive date window
into every HealthKit anchored-query family. Queries now use a strict start-date
predicate, so out-of-window samples and their deletion stream never enter the
export page. Existing callers remain unbounded until a destination scope is
supplied.
