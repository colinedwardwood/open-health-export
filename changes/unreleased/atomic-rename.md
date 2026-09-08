# Atomic file replace on Linux

Overwrite the destination with POSIX `rename` instead of `replaceItemAt`, which
can delete the target and leave no replacement on swift-corelibs-foundation.
