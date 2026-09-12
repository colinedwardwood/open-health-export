A force-quit after the destination write and before acknowledgement leaves
the batch pending in SQLite. The next open reconstructs the queue from that
store, not from transport session state.
