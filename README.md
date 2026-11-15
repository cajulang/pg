# pg

A PostgreSQL client for [Caju](https://github.com/cajulang/cajulang), written in Caju: it
speaks PostgreSQL's frontend/backend protocol (version 3) directly over TCP or TLS, with no C
library.

```caju
import "github.com/cajulang/pg"

db, err := pg.connect("postgres://app:secret@127.0.0.1:5432/shop")
if err != nil { panic(err.Error()) }

rows, err := db.query("select id, name, price from products where price < $1 order by id", []any{10})
while rows.next() {
  print(rows.get_int("id"), rows.get_str("name"), rows.get_str("price"))
}

res, err := db.exec("update products set price = $1 where id = $2", []any{"9.90", 7})
print(res.rows_affected)
```

## What it does

- **Connecting:** a URL (`postgres://user:password@host:port/db?application_name=x`) or
  `key=value` settings (`host=… port=… user=… password=… dbname=…`). The host is an IPv4 address
  or a name (`/etc/hosts`, then DNS: `db.internal`, a Kubernetes service). Settings:

  | Setting | |
  |---|---|
  | `host`, `port`, `user`, `password`, `dbname`, `application_name` | as in libpq |
  | `connect_timeout` | seconds to connect; TLS and authentication must also finish in that time (30 s when it is 0) |
  | `sslmode` | `disable` (the default), `allow`, `prefer`, `require` or `verify-full`; see TLS below |
  | `sslrootcert` | a PEM file with the CA for `verify-full` (empty or `system`: the system's roots) |
  | `require_auth` | the authentication methods the server may ask for; see below |
  | `query_timeout` | seconds a query may take (0: no limit); then it is canceled and the connection closed |
  | `max_message` | the largest message accepted from the server, in bytes (default 64 MiB) |

  An unknown setting, or a NUL byte (`%00`) in any value, is an error. Errors never repeat the
  DSN or the values in it, so a password does not end up in a log.
- **Authentication:** SCRAM-SHA-256 (PostgreSQL's default since version 14), md5, a password in
  clear text, or none (trust). With SCRAM the client checks the server's signature, and the
  exchange must finish before the server may say the login worked.
- **`require_auth`** lists the methods the server may ask for (`scram-sha-256`, `md5`,
  `password`, `none`, separated by commas). By default only `scram-sha-256` is accepted, unless
  the connection is TLS with a verified certificate (`sslmode=verify-full`): then any. This stops
  a fake server or anyone in the middle from asking for the password in clear text or as an md5
  hash, or from skipping authentication. The password is never sent for a method that is not
  allowed. For an md5 or trust server, say so: `?require_auth=md5` or `?require_auth=none`.
- **TLS** (`sslmode`): `require` encrypts but does not check the certificate (anyone in the
  middle can present one); `verify-full` checks the chain against `sslrootcert` and the host name;
  `prefer` uses TLS when the server offers it, otherwise goes on without it; `allow` connects
  without TLS and tries TLS only if the server refuses that. Only `verify-full` protects against
  someone in the middle. `verify-ca` is refused (std/tls checks the chain together with the
  name). `c.uses_tls()` and `c.tls_verified()` tell what a connection got.
- **Queries** (`query`, `query_row`, `exec`) always go through the extended protocol, with or
  without arguments (`$1`, `$2`…). The values travel apart from the SQL, so there is no injection,
  and the SQL is a single statement.
- **`exec_script(sql)`** uses the simple protocol and runs several statements separated by `;`,
  which is handy for migrations. It takes no arguments: never build its SQL out of user input.
- **Types:** results come back as Caju values.

  | PostgreSQL | Caju |
  |---|---|
  | `smallint` `integer` `bigint` `oid` | `int` |
  | `real` `double precision` | `num` |
  | `boolean` | `bool` |
  | `bytea` | `str` with the raw bytes |
  | `numeric` | `str`, so precision is kept (`get_num` converts it) |
  | `text` `varchar` `json` `jsonb` `uuid` dates and the rest | `str`, as PostgreSQL writes them |
  | `NULL` | `nil` |

  As arguments: `nil`, `bool`, `int`, `num`, `str`, and `pg.bytes(data)` for `bytea`.
- **Errors:** the server's errors arrive as `*pg.PgError`, with `code` (the SQLSTATE), `message`,
  `detail`, `hint` and `position`. After an error the connection keeps working.
- **A server that misbehaves** cannot crash the client or make it allocate without limit: every
  message is checked against its length (and the rows against their description), and lengths
  below 4 or above `max_message` are refused. Such a protocol error closes the connection.
- **Timeouts and cancel:** with `query_timeout`, a query that takes longer is canceled (a
  CancelRequest on a new connection) and the connection is closed. `c.cancel()` sends one on
  request.
- **COPY** is not supported: `COPY ... FROM STDIN` is ended with CopyFail and `COPY ... TO STDOUT`
  is skipped, both with an error, and the connection keeps working.
- **Transactions:** `begin` / `commit` / `rollback`, or `transaction(fn)`, which commits when the
  function returns `nil` and rolls back when it returns an error.
- **Pool:** `pg.open(dsn, max)` keeps up to `max` connections and reuses them. A connection that
  comes back is reset before the next caller gets it: a transaction still open is rolled back,
  then `DISCARD ALL` (settings, `SET ROLE`, prepared statements, temporary tables, `LISTEN`) and
  `pg_advisory_unlock_all()`. If the reset fails, or the session is not idle after it, the
  connection is closed instead. This costs one round trip per `release`.

## API

| | |
|---|---|
| `pg.connect(dsn) -> (*Conn, error)` | opens a connection |
| `pg.connect_config(cfg)` | the same, from a `*pg.Config` (`pg.parse_dsn(dsn)`) |
| `c.query(sql, args) -> (*Rows, error)` | the rows of a query |
| `c.query_row(sql, args) -> (*Rows, error)` | the first row (already selected); an error if there is none |
| `c.exec(sql, args) -> (*Result, error)` | runs one statement; `res.rows_affected`, `res.tag` |
| `c.exec_script(sql) -> (*Result, error)` | runs several statements, without arguments (simple protocol) |
| `c.cancel()`, `c.reset()` | cancels what the connection runs; resets its session (as the pool does) |
| `c.backend_pid()`, `c.uses_tls()`, `c.tls_verified()` | |
| `c.begin()`, `c.commit()`, `c.rollback()` | transactions |
| `c.transaction(fn(tx: *pg.Conn) -> error)` | commit or roll back depending on the result |
| `c.in_transaction()`, `c.parameter_status(name)`, `c.close()` | |
| `rows.next()`, `rows.len()` | walks the rows |
| `rows.get(col)`, `rows.at(i)`, `rows.values()`, `rows.is_null(col)` | the current row's values |
| `rows.get_str/get_int/get_num/get_bool(col)` | converted, with the zero value for `NULL` |
| `rows.maps() -> []map[str]any` | every row as a map |
| `pg.open(dsn, max) -> (*Pool, error)` | a pool: `query`, `query_row`, `exec`, `transaction`, `acquire`/`release`, `stats`, `close` (`pg.open_config(cfg, max)` from a `*pg.Config`) |
| `pg.ident(name)` | quotes an identifier (`"order"`) |

## Limits

- **TLS with PostgreSQL 17 and older.** In TLS 1.3 std/tls only has the X25519 group, and those
  servers only offer one curve (`ssl_ecdh_curve`, `prime256v1` by default, which cannot be
  X25519), so the handshake fails. Set `ssl_max_protocol_version = 'TLSv1.2'` on them (TLS 1.2
  with ECDHE P-256 works). PostgreSQL 18 (`ssl_groups` includes X25519) works as it comes.
- **Not supported:** channel binding (SCRAM-SHA-256-PLUS), client certificates and `verify-ca`.
- **Results are read whole.** A query reads all its rows into memory before returning. For very
  large results, page with `limit`/`offset` or a cursor.
- **The pool is sequential.** Caju has no threads yet, so it reuses connections but does not
  serve concurrent callers.
- **Not supported yet:** `COPY`, `LISTEN`/`NOTIFY` and Unix sockets.

## Performance

Against node-postgres 8.23, on PostgreSQL 17 over the local network (median of 3 runs; `bench/`):

| | node-postgres | pg (Caju) |
|---|--:|--:|
| Connecting (SCRAM-SHA-256) | 13 ms | 37 ms |
| 1,000 INSERTs in a transaction | 190 ms | 114 ms |
| 2,000 SELECTs with an argument | 450 ms | 305 ms |
| Reading 100,000 rows | 87 ms | 146 ms |
| Process memory (RSS) | 98 MB | 37 MB |

- Round trips cost less: one write per query, and no promises or event loop in the way.
- Connecting costs more: SCRAM's 4,096 rounds of PBKDF2 run in Caju, where Node uses OpenSSL.
  With a pool, the connection is made once.
- Reading a large result is slower: each value is copied and decoded on its own.

## Requirements

Caju 0.9.0 or newer (std/tls, `os.sleep`, host names, timeouts and byte-exact string slices).

## Tests

```sh
caju test                                   # unit tests (DSN, values, messages, SCRAM from RFC 7677)
                                            # and security_test.caju, against a fake hostile server
                                            # (testdata/fake_server.caju, built and started by it)
tools/test-db.sh                            # a PostgreSQL 17 in Docker, with SCRAM-SHA-256 and TLS
                                            # (or any server: the tests create table caju_items)
PG_TEST_DSN=postgres://caju:caju-test@127.0.0.1:55432/caju PG_TEST_ROOT=<the CA it prints> caju test
caju run examples/demo.caju                 # a tour
```

## License

MIT
