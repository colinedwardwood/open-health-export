### Emitted index on delta commit

Each sample UUID is upserted into `emitted_index` in the same write-ahead
transaction as the cursor, census, and dirty day. A later send of the same UUID
replaces digest and batch id. A fault inside that transaction rolls the index
back with the cursor.
