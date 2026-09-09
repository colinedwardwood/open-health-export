MQTT destinations complete the same R-25 enablement path as HTTPS: canary
preview, pin-without-TLS for `mqtt://`, CONNECT/PUBLISH/PUBACK on a real
pipe, then `DestinationSetup.enable`. QoS 0 remains `sentUnconfirmed`.
