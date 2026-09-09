Named properties P1/P2/P15 now have shrinking NDJSON/JSON round-trips, byte-identical
re-export, and a DEBUG fault on atomic rename so a crash before `rename` cannot tear
the destination. MQTT topics accept 256 bytes and reject a UInt16 overflow; a local
Mosquitto process is restarted mid-publish when the broker binary is on PATH.
