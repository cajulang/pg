#!/bin/sh
# Starts a PostgreSQL for the integration tests in Docker (port 55432, SCRAM-SHA-256), then:
#   PG_TEST_DSN=postgres://caju:caju-test@127.0.0.1:55432/caju caju test
#   tools/test-db.sh stop      removes it
set -e
NAME=caju-pg-test
if [ "$1" = "stop" ]; then docker rm -f $NAME >/dev/null; exit 0; fi
docker rm -f $NAME >/dev/null 2>&1 || true
docker run -d --name $NAME -p 127.0.0.1:55432:5432 \
  -e POSTGRES_USER=caju -e POSTGRES_PASSWORD=caju-test -e POSTGRES_DB=caju \
  -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 -e POSTGRES_INITDB_ARGS=--auth=scram-sha-256 \
  postgres:17-alpine >/dev/null
until docker exec $NAME pg_isready -U caju -d caju >/dev/null 2>&1; do sleep 1; done
sleep 1
echo "PG_TEST_DSN=postgres://caju:caju-test@127.0.0.1:55432/caju"
