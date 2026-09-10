The Mosquitto contract harness now stops a broker on a deadline. `waitUntilExit()` has
none, so a broker that did not act on SIGTERM parked the entire test run instead of
failing the one test that owned it. The Darwin path now escalates to SIGKILL on the same
bounded schedule the Glibc path already used.
