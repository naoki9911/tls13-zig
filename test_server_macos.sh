#!/bin/bash

set -eux -o pipefail

# force to use brew's curl
CURL="/opt/homebrew/opt/curl/bin/curl"

# force to use LibreSSL
OPENSSL="/usr/bin/openssl"

function cleanup() {
    set +e
    kill $ZIG_SERVER_PID
    echo "exit"
}

trap cleanup EXIT

cd $(dirname $0)

cd test

# macos uses libressl as an alias for openssl.
# libressl does not have dh parameter x448.
unames=$(uname -s)
case "$unames" in
    Linux*)     DH_X448="x448:";;
    Darwin*)    DH_X448="";;
    *)          echo "Unknown HOST_ARCH=$(uname -s)"; exit 1;;
esac

# Generate testing certificate
./gen_cert.sh

cd ../

# Checking memory leak
until nc -z localhost 8443; do sleep 1; done && curl https://localhost:8443 --insecure &
zig test src/main_test_server.zig --test-filter 'e2e server'
echo "Memory leak check passed"

zig run src/main_test_server.zig &
ZIG_SERVER_PID=$!

# wait for server becoming ready
until nc -z localhost 8443; do sleep 1; done

echo "READY"

$CURL https://localhost:8443 --tlsv1.3 --insecure | grep tls13-zig

# Testing Resumption
echo "GET / " | $OPENSSL s_client -servername localhost -connect localhost:8443 -ign_eof -sess_out sess.pem | grep tls13-zig
echo "GET / " | $OPENSSL s_client -servername localhost -connect localhost:8443 -ign_eof -sess_in sess.pem | grep tls13-zig
