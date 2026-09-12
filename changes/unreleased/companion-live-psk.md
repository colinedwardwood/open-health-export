Live Mac companion receive now runs against a TLS-PSK loopback listener and a
phone `NWByteStream`, not only the in-process loopback broker. Darwin
Network.framework PSK is TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256` (Apple
TN3213: no TLS 1.3 PSK on `NWConnection`).
