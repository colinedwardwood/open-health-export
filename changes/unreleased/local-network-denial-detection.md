A revoked Local Network grant is now detected and reported as itself. The app already
carried the copy — "Local Network access is off for this app, so it cannot find your
Mac. That is different from the Mac being asleep or on another network" — and an error
class and run outcome to go with it, but nothing in the product could ever produce
them: a denial reached the user as `serviceNotFound` and rendered the unreachable copy,
telling them to wake a Mac that was never asleep.

The companion browser now watches its own state instead of only its results, so the
mDNS policy error that a denied grant produces is read as a denial rather than as an
empty network, and it is reported immediately rather than after the browse window
elapses. On the socket, `EPERM` counts as a denial only on a dial that needed the grant,
because the same code on public unicast means something else.

Transport failures are also normalized onto closed `DestinationSendError` values at the
companion pipe. `DeliveryExecutor` classifies `DestinationSendError` and regards anything
else as transient, so before this a denial would have been retried indefinitely against
a permission only the user can change. A pin mismatch and a SEC-15 address-class stop
are deliberately left unmapped: both are worse than unreachable and own their own paths.

Revoking the grant on a real device remains device-only evidence; the simulator cannot
produce the condition. What is covered here is the classification and the plumbing,
including that a genuinely absent Mac still reports unreachable.
