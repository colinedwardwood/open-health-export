QA-11 / R-90: encode QoS 2 and last-will as explicit architectural
exclusions instead of silently coercing configuration to QoS 1. Loopback and
Mosquitto contracts verify rejection before dial and that CONNECT carries no
will fields.
