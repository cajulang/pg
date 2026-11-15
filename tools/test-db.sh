#!/bin/sh
# Starts a PostgreSQL for the integration tests in Docker (port 55432, SCRAM-SHA-256, TLS with a
# test CA made here by openssl), then prints the variables for:
#   PG_TEST_DSN=... PG_TEST_ROOT=... caju test
#   tools/test-db.sh stop      removes it
# PG_TEST_CONTAINER names the container (default caju-pg-test), PG_TEST_IMAGE the image (default
# postgres:17-alpine). PostgreSQL 17 and older offer only one TLS 1.3 group (ssl_ecdh_curve,
# prime256v1) and std/tls has only X25519 in TLS 1.3, so they are capped at TLS 1.2 here.
set -e
NAME=${PG_TEST_CONTAINER:-caju-pg-test}
CERTS=${TMPDIR:-/tmp}/$NAME-certs
if [ "$1" = "stop" ]; then
  docker rm -f "$NAME" >/dev/null
  rm -rf "$CERTS"
  exit 0
fi
docker rm -f "$NAME" >/dev/null 2>&1 || true
# a CA and a server certificate for 127.0.0.1 and pg.test (not for localhost: the tests use it
# to check that a wrong host name is refused)
rm -rf "$CERTS"
mkdir -p "$CERTS"
cd "$CERTS"
openssl ecparam -name prime256v1 -genkey -noout -out ca.key 2>/dev/null
openssl req -x509 -new -key ca.key -sha256 -days 30 -subj "/CN=caju-pg test CA" -out ca.pem 2>/dev/null
openssl ecparam -name prime256v1 -genkey -noout -out server.key 2>/dev/null
openssl req -new -key server.key -subj "/CN=pg.test" -out server.csr 2>/dev/null
printf "subjectAltName=IP:127.0.0.1,DNS:pg.test\nextendedKeyUsage=serverAuth\n" > ext.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -sha256 -extfile ext.cnf -out server.pem 2>/dev/null
chmod 644 server.key
IMAGE=${PG_TEST_IMAGE:-postgres:17-alpine}
TLSOPT="-c ssl_max_protocol_version=TLSv1.2"
case "$IMAGE" in postgres:1[89]*|postgres:[2-9]*) TLSOPT="" ;; esac
docker run -d --name "$NAME" -p 127.0.0.1:55432:5432 -v "$CERTS":/certs:ro \
  -e POSTGRES_USER=caju -e POSTGRES_PASSWORD=caju-test -e POSTGRES_DB=caju \
  -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 -e POSTGRES_INITDB_ARGS=--auth=scram-sha-256 \
  -e TLSOPT="$TLSOPT" --entrypoint sh "$IMAGE" -c '
    install -o postgres -m 600 /certs/server.key /var/lib/postgresql/server.key
    install -o postgres -m 644 /certs/server.pem /var/lib/postgresql/server.pem
    exec docker-entrypoint.sh postgres -c ssl=on $TLSOPT \
      -c ssl_cert_file=/var/lib/postgresql/server.pem -c ssl_key_file=/var/lib/postgresql/server.key' >/dev/null
until docker exec "$NAME" pg_isready -U caju -d caju >/dev/null 2>&1; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ]; then docker logs "$NAME" | tail -5; exit 1; fi
  sleep 1
done
sleep 1
echo "PG_TEST_DSN=postgres://caju:caju-test@127.0.0.1:55432/caju"
echo "PG_TEST_ROOT=$CERTS/ca.pem"
