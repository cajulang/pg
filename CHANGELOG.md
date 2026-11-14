# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

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

[0.2.0]: https://github.com/cajulang/pg/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cajulang/pg/releases/tag/v0.1.0
