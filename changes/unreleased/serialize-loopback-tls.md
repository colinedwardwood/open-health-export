### Stabilize loopback TLS tests

Serializes the MQTT loopback integration suite so concurrent Security-framework imports cannot
race while loading the shared PKCS#12 fixture.
