### Destination path test and widget snapshot file

A destination cannot enable until a named-step R-25 test returns `passed` or
`sentUnconfirmed`. Local folder tests write a canary and confirm the bytes;
MQTT QoS 0 is never a pass. After each run the engine writes a JSON status
snapshot for the widget and watchdog, without opening SQLite.
