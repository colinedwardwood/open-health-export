### Linux HTTP transport import

`URLSessionHTTPTransport` conditionally imports `FoundationNetworking`, where Linux Swift exposes
`URLSession`, `URLRequest`, and `HTTPURLResponse`.
