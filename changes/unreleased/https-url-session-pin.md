Pinned HTTPS POST uses `URLSession` with the stored leaf pin as trust (R-31), so a
self-signed Home Assistant webhook works after TOFU. Darwin loopback HTTPS proves
enablement and a mismatched pin. The harness MQTT destination picker persists QoS 0 or 1.
Mosquitto rejects anonymous CONNECT when a password file is required and accepts the
matching username.
