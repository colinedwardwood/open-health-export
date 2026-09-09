Named P8, P9, and P11 tests: locale-invariant repeated encodes, order-independent
day folds, and stable bucket keys when a day is recomputed with more samples.
In-memory day folds sort by record identity before summing so IEEE addition
cannot depend on query order.

