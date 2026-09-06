### MQTTS over pinned TLS

`MQTTSink.overNetwork` dials `mqtts` through `NWByteStream`. A matching leaf pin is sufficient
trust — system CAs do not override TOFU, which is how a self-signed home broker works. Darwin
tests speak MQTTS on loopback with a throwaway identity; a wrong pin fails before PUBLISH.
