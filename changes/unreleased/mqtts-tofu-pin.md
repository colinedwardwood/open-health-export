MQTTS first use now TOFUs a self-signed broker (R-31): the handshake captures the
leaf and DestinationSetup pins it. The harness stores that pin, MQTT username, and
a keychain password so later exports present the same identity and credentials.
