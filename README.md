<p align="center">
  <img src="https://santoku.dev/logo-santoku-imap.png" height="64" alt="santoku-imap">
</p>

# santoku-imap

An IMAP4rev1 client subset: LOGIN, EXAMINE, UID SEARCH, UID FETCH (including
X-GM-THRID and header fields), APPEND, and LIST with SPECIAL-USE detection.
Runtime-agnostic: the core takes an injected stream driver, and companion
modules cover header parsing with RFC 2047 decoding, threading with a
References fallback, and a minimal draft builder.

## Drivers

The driver contract is push-shaped:

```lua
driver.connect({
  host = "imap.example.com",
  port = 993,
  data = function (chunk) end,
  closed = function (err) end,
}, function (ok, conn) end)

conn.write(data)
conn.close()
```

Data arrives via the `data` callback in arbitrary fragmentation; the core
reassembles lines and IMAP literals. Pull-based drivers (blocking runtimes
with no event loop) additionally expose `conn.step(ms)`, one bounded read
delivered through `data`; the core detects it and pumps internally during
connect and each command, so consumers see the same callback API on every
runtime, with completion synchronous on pull drivers and event-driven on push
drivers. `step_ms` and `timeout_ms` on connect opts bound the pumping; a
command exceeding `timeout_ms` with no server bytes fails and closes the
connection.

Drivers per runtime: `santoku.socket.stream` (luasocket and luasec),
`santoku.web.stream` (node tls under wasm), `santoku.resty.stream`
(ngx cosockets), or any app-provided bridge implementing the contract.

## Documentation

Documentation and runnable examples across the santoku ecosystem: [santoku.dev](https://santoku.dev).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## License

MIT, see [LICENSE](LICENSE).
