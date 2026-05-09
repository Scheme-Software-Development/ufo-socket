#!/bin/bash
# Automated test runner for ufo-socket.
set -e

cd "$(dirname "$0")/.."

# Load akku environment so Chez can find libraries.
if [ -f .akku/env ]; then
    eval "$(.akku/env -s)"
fi

echo "=== Building ==="
make

echo "=== Test 1: Echo server/client ==="
timeout 5 scheme --script tests/server.ss &
SERVER_PID=$!
sleep 1
CLIENT_OUT=$(timeout 3 scheme --script tests/client.ss || true)
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

if echo "$CLIENT_OUT" | grep -q "received 'hello"; then
    echo "PASS: Echo test"
else
    echo "FAIL: Echo test"
    echo "$CLIENT_OUT"
    exit 1
fi

echo "=== Test 2: Unit tests (UDP, errors, bytevector) ==="
if scheme --script tests/unit.ss; then
    echo "PASS: Unit tests"
else
    echo "FAIL: Unit tests"
    exit 1
fi

echo "=== Test 3: Multicast (best effort) ==="
timeout 6 scheme --script tests/multicast.ss c4 > /tmp/mcast-consumer.log 2>&1 &
CONSUMER_PID=$!
sleep 1
timeout 2 scheme --script tests/multicast.ss p4 > /dev/null 2>&1 || true
sleep 2
kill $CONSUMER_PID 2>/dev/null || true
wait $CONSUMER_PID 2>/dev/null || true

if grep -q "received msg:" /tmp/mcast-consumer.log; then
    echo "PASS: Multicast test"
else
    echo "SKIP: Multicast test (no multicast traffic received; common in containers/VMs)"
fi

echo "=== All required tests passed ==="
