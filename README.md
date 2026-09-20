<p align="center">
  <img src="https://santoku.dev/logo-santoku-imap.png" height="64" alt="santoku-imap">
</p>

# santoku-imap

An IMAP4rev1 client subset: LOGIN, EXAMINE, UID SEARCH, UID FETCH (including
X-GM-THRID and header fields), APPEND, and LIST with SPECIAL-USE detection.
Runtime-agnostic: the core takes an injected stream driver, and companion
modules cover header parsing with RFC 2047 decoding, threading with a
References fallback, and a minimal draft builder.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-imap).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## License

MIT, see [LICENSE](LICENSE).
