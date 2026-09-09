Add a POSIX plaintext MQTT dial so Linux can reach a real Mosquitto, plus a
catalogue-generated Home Assistant container job that asserts statistics rows
exist after a recorder cycle. QoS 0 stays `unknownAck`. TLS MQTTS remains
Darwin-only until a portable TLS stream exists.
