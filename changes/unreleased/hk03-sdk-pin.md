The HealthKit SDK pin now matches HKTypeIdentifiers.h on the current macOS SDK.
Three new header identifiers still return nil from HealthKit type constructors, so
they are excluded with that reason until the SDK actually vends the types.
