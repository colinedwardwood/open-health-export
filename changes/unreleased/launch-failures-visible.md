Launch and background failures (observer registration, wake log, recovery, queue
expiry, observer-triggered export) are journalled with an error class and shown on
Status instead of being discarded. A keychain sealed before first unlock is reported as
locked and retried on the next wake, not as a missing credential (#62).
