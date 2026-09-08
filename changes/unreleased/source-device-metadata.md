### Preserve HealthKit source and device identity

Quantity records now carry the HealthKit writing source, non-serial device descriptors, and the
user-entered flag through the domain and `ohe.wire/1`. The data browser names the source, and the
synthetic corpus deterministically covers six clearly synthetic source identities.
