### R-01 persisted dirty-day catch-up

Export runs now drain persisted dirty days even when the anchored delta is empty, refetch full-day
samples before local folds, and give revised aggregate generations distinct idempotency keys.
Headers publish the measurement-time `completeThrough` watermark, while checkpoints record the
declared tzdata version rather than the app version.
