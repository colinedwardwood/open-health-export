Darwin HTTPS canaries can speak HTTP/2: a loopback peer advertises ALPN `h2` and a
minimal framer accepts the connection preface, then `URLSession` POSTs a gzip body
and gets 204. Linux stays on HTTP/1.1 without a TLS stack in-repo.
