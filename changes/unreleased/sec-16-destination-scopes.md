SEC-16: replace the global Health metric selection with fail-closed,
per-destination scopes for the local archive, HTTPS, MQTT and Mac companion.
Each new destination starts with zero types; users explicitly choose types,
an inclusive start date and an optional exclusive end date, with Core Daily
available only as an explicit preset. Authorization and background observers
use the union of enabled scopes, while reads, reconciliation, backfill and
queued delivery enforce the destination's metric and date grant.
