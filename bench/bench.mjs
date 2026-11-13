// The same work as bench.caju, with node-postgres: npm install pg; PG_DSN=... node bench/bench.mjs
import pg from "pg"
const dsn = process.env.PG_DSN
const t = () => performance.now()
let t0 = t()
const c = new pg.Client({ connectionString: dsn })
await c.connect()
const connect = t() - t0
await c.query("drop table if exists bench; create table bench (id int primary key, name text, price float8)")
t0 = t()
await c.query("begin")
for (let i = 0; i < 1000; i++) await c.query("insert into bench values ($1, $2, $3)", [i, "item " + i, i * 1.5])
await c.query("commit")
const inserts = t() - t0
t0 = t()
let sum = 0
for (let i = 0; i < 2000; i++) { const r = await c.query("select name, price from bench where id = $1", [i % 1000]); sum += r.rows[0].price }
const selects = t() - t0
t0 = t()
const big = await c.query("select g as n, 'row ' || g as s, g * 0.5 as f from generate_series(1, 100000) g")
let total = 0
for (const r of big.rows) total += r.n
const bigms = t() - t0
await c.end()
console.log(JSON.stringify({ connect, inserts, selects, big: bigms, check: [sum, total] }))
