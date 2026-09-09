Linux CI drops the Google Chrome apt source before `apt-get update` so a
third-party hash mismatch cannot fail zlib/Mosquitto install. The HTTP
loopback listener uses Glibc's `SOCK_STREAM` enum on Linux.
