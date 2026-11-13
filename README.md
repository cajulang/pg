# pg

A PostgreSQL client for [Caju](https://github.com/aecdanjundex/cajulang), written in Caju: it
speaks PostgreSQL's frontend/backend protocol (version 3) directly over TCP, with no C library.

```caju
import "github.com/aecdanjundex/pg"

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
  `key=value` settings (`host=… port=… user=… password=… dbname=…`).
- **Authentication:** trust, password, md5 and SCRAM-SHA-256, PostgreSQL's default since
  version 14. With SCRAM it also checks the server's signature.
- **Queries with arguments** (`$1`, `$2`…) go through the extended protocol. The values travel
  apart from the SQL, so there is no injection.
- **`exec` without arguments** uses the simple protocol and can run several statements separated
  by `;`, which is handy for migrations.
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
- **Transactions:** `begin` / `commit` / `rollback`, or `transaction(fn)`, which commits when the
  function returns `nil` and rolls back when it returns an error.
- **Pool:** `pg.open(dsn, max)` keeps up to `max` connections and reuses them. A connection that
  comes back with a transaction still open is rolled back first.

## API

| | |
|---|---|
| `pg.connect(dsn) -> (*Conn, error)` | opens a connection |
| `pg.connect_config(cfg)` | the same, from a `*pg.Config` (`pg.parse_dsn(dsn)`) |
| `c.query(sql, args) -> (*Rows, error)` | the rows of a query |
| `c.query_row(sql, args) -> (*Rows, error)` | the first row (already selected); an error if there is none |
| `c.exec(sql, args) -> (*Result, error)` | runs a statement; `res.rows_affected`, `res.tag` |
| `c.begin()`, `c.commit()`, `c.rollback()` | transactions |
| `c.transaction(fn(tx: *pg.Conn) -> error)` | commit or roll back depending on the result |
| `c.in_transaction()`, `c.parameter_status(name)`, `c.close()` | |
| `rows.next()`, `rows.len()` | walks the rows |
| `rows.get(col)`, `rows.at(i)`, `rows.values()`, `rows.is_null(col)` | the current row's values |
| `rows.get_str/get_int/get_num/get_bool(col)` | converted, with the zero value for `NULL` |
| `rows.maps() -> []map[str]any` | every row as a map |
| `pg.open(dsn, max) -> (*Pool, error)` | a pool: `query`, `query_row`, `exec`, `transaction`, `acquire`/`release`, `stats`, `close` |
| `pg.ident(name)` | quotes an identifier (`"order"`) |

## Limits

- **No TLS.** Caju has no TLS yet, so use it on a private network, on the same machine or through
  a tunnel. `sslmode=require` is refused rather than silently ignored.
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

## Tests

```sh
caju test                                   # unit tests (DSN, values, messages, SCRAM from RFC 7677)
tools/test-db.sh                            # a PostgreSQL 17 in Docker, with SCRAM-SHA-256
                                            # (or any server: the tests create table caju_items)
PG_TEST_DSN=postgres://caju:caju-test@127.0.0.1:55432/caju caju test
caju run examples/demo.caju                 # a tour
```

## License

MIT
