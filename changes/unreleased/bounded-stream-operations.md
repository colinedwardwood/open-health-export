Every `NWByteStream` operation now has a deadline. A broker that completes the TLS
handshake and then refuses us — an mTLS listener we hold no client certificate for —
acknowledges neither the write nor a read, so an export to it parked forever with no
R-21 outcome. Writes and reads now fail closed with `StreamError.readTimeout`.

The two Mosquitto TLS contract tests also moved into a serialized suite: each binds a
listener and imports PKCS#12 material, and running them alongside the rest of the suite
left brokers and Security-framework imports contending.
