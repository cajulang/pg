# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-11-15

Security fixes from an audit (findings M-1 to M-10). Several change behaviour: read the
**Breaking** entries before upgrading.

### Security
- **Authentication downgrade (M-3).** A fake server, or anyone in the middle, could ask for the
  password in clear text or as an md5 hash, send AuthenticationOk in the middle of SCRAM (before
  proving it knows the password), or send ReadyForQuery with no authentication at all, and the
  client went along. Now a SCRAM exchange must end with the server's verified signature before
  AuthenticationOk, nothing but authentication may come before AuthenticationOk, and the new
  `require_auth` setting lists the methods the server may ask for; the password is never sent
  for any other.
- **NUL bytes in the DSN (M-1).** `%00` in a URL setting injected extra startup parameters
  (`/shop%00options%00-c search_path=evil`). A NUL byte in any setting, in a `Config` built by
  hand or in SQL is now an error, and unknown settings (such as `options`) are refused.
- **The password in error messages (M-2).** `bad port in "<the whole DSN>"` repeated the
  password. Errors no longer repeat the DSN, and name only keys libpq knows.
- **Message lengths (M-5, M-6).** A length above 2 GB made the client buffer without limit, and a
  short or negative length, a short message or a DataRow with more columns than its
  RowDescription crashed it (index out of range) or desynchronised it. Every message is now read
  with bounds checks, lengths below 4 or above `max_message` (64 MiB by default) are refused, and
  any such protocol error closes the connection.
- **Dirty pooled sessions (M-8).** The pool handed out connections with the previous caller's
  `SET`, `SET ROLE`, temporary tables, prepared statements, `LISTEN` and advisory locks. `release`
  now runs `DISCARD ALL` and `pg_advisory_unlock_all()` and closes the connection if that fails or
  leaves it anything but idle.
- **SCRAM iterations (M-4).** A server could ask for any number of PBKDF2 rounds; above
  `pg.MAX_SCRAM_ITERATIONS` (600,000) the login is refused. A server nonce must also be longer
  than the client's, and unknown mandatory extensions are refused.
- **Hangs (M-7).** A server that stopped answering hung the client forever, and `COPY` hung it
  too. Connecting (TLS and authentication included) now has a deadline, queries can have one
  (`query_timeout`, which also cancels the statement on the server), and COPY ends with an error.
- **sslmode (M-10).** `prefer` and `allow` were accepted and silently meant no TLS. They now do
  what libpq does, with real TLS.

### Added
- TLS through std/tls: `sslmode=require`, `verify-full` (with `sslrootcert`), `prefer` and
  `allow`. Data a server sends before the TLS handshake is refused (as in CVE-2021-23222).
  `c.uses_tls()`, `c.tls_verified()`.
- `require_auth` (`scram-sha-256`, `md5`, `password`, `none`), as in libpq.
- `query_timeout` and `max_message` settings; `c.cancel()`, `c.reset()`, `c.backend_pid()`,
  `c.exec_script(sql)`, `pg.open_config(cfg, max)`, `pg.auth_methods`.
- `security_test.caju`: the client against a hostile fake server (testdata/fake_server.caju);
  `tools/test-db.sh` now also sets up TLS with a test CA.

### Changed
- **Breaking:** `require_auth` defaults to `scram-sha-256` unless the connection is TLS with a
  verified certificate. Servers that use md5, a password in clear text or trust need
  `require_auth=md5`, `require_auth=password` or `require_auth=none` (or a list).
- **Breaking:** `exec` always uses the extended protocol, so it runs one statement even without
  arguments. Scripts with several statements go through the new `exec_script(sql)`.
- **Breaking:** unknown DSN settings are an error instead of being ignored.
- **Breaking:** needs Caju 0.9.0 (`caju = "0.9.0"` in caju.toml) for std/tls.
- The pool's `release` costs a round trip (the reset).
- Errors from the socket start with `pg: `; a protocol error closes the connection.

## [0.2.0] - 2026-11-14

### Added
- Host names: `postgres://app@db.internal/shop` connects through `net.resolve` (`/etc/hosts`, then
  DNS), so service names in Kubernetes or Docker Compose work. Before, only IPv4 addresses and
  `localhost` did.
- `connect_timeout` (seconds), in the URL or in `key=value` settings, as in libpq.

### Changed
- Needs Caju 0.6.0 (`caju = "0.6.0"` in caju.toml).
- Connection errors start with `pg: `.
- Protocol bytes are sliced with `s[a:b]` (byte-exact since Caju 0.6.0) instead of a copy loop.

## [0.1.0] - 2026-11-13

### Added
- The first release: the protocol over TCP, trust/password/md5/SCRAM-SHA-256, parameters,
  transactions and a pool.

[0.3.0]: https://github.com/cajulang/pg/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cajulang/pg/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cajulang/pg/releases/tag/v0.1.0
