Darwin HTTPS canaries can speak HTTP/2: a loopback peer advertises ALPN `h2` and a
minimal framer accepts the connection preface, then `URLSession` POSTs a gzip body
and gets 204. Linux (and Darwin) also speak prior-knowledge HTTP/2 over plaintext
TCP so QA-10's framer runs without an in-repo TLS stack. TLS+ALPN remains Darwin-only.

