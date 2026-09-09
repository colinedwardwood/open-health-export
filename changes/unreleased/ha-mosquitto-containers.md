Add a POSIX plaintext MQTT dial so Linux can reach a real Mosquitto, plus a
catalogue-generated Home Assistant container job that asserts statistics rows
exist with the expected sum/mean shape after a recorder cycle and that an
enum/measurement entity is excluded. QoS 0 stays `unknownAck`. TLS MQTTS
remains Darwin-only until a portable TLS stream exists. The HA WebSocket uses
Foundation on Darwin and an RFC 6455 POSIX path on Linux, where
FoundationNetworking's libcurl build does not support WebSockets.
