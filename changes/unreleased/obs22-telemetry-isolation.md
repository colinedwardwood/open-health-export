OBS-22: assert the telemetry subsystem opens no connection in its default
configuration, with a real loopback listener reachable throughout so that only
the configuration is what prevents egress. The export cycle's half of R-52 was
already covered; the telemetry half, which is what the requirement names, was
not. Includes the control case — telemetry enabled and pointed at the listener
is seen by both the egress recorder and the listener — so a silently broken
interceptor cannot make the zero-egress assertion pass forever.
