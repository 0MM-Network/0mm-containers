#!/bin/bash

# Script to test the generated Vault shim

# Assume shim is generated in $PWD/vault

SCRIPTS_DIR="$PWD"

echo "Testing against real transit at 8200..."
export TRANSIT_ADDR="http://127.0.0.100:8200"
export VAULT_ADDR="http://127.0.0.100:8100"

# Pre-test check: Retry status against TRANSIT_ADDR
LAST_ERROR=""
ATTEMPTS=10
for ((i=1; i<=$ATTEMPTS; i++)); do
  if "$SCRIPTS_DIR/vault" status; then
    break
  else
    LAST_ERROR=$("$SCRIPTS_DIR/vault" status 2>&1 || true)
    if [ $i -eq $ATTEMPTS ]; then
      echo "Transit status check failed after $ATTEMPTS attempts: $LAST_ERROR"
      exit 1
    fi
    sleep 2
  fi
done

export TEST_VAULT_TOKEN="$(secret-tool lookup vault zero policy root | head)"

# Start server in background for testing (kill after)
"$SCRIPTS_DIR/vault" server > vault-test.log 2>&1 &
SERVER_PID=$!
sleep 10  # Wait longer for server to start and auto-unseal
if "$SCRIPTS_DIR/vault" version &>/dev/null; then
  "$SCRIPTS_DIR/vault" version && echo "✅ Version check passed" || echo "❌ Version failed"
  ATTEMPTS=30
  SUCCESS=false
  for ((i=1; i<=$ATTEMPTS; i++)); do
    STATUS=$("$SCRIPTS_DIR/vault" status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Sealed.*false"; then
      echo "✅ Status check passed (unsealed)"
      SUCCESS=true
      break
    fi
    sleep 1
  done
  if ! $SUCCESS; then echo "❌ Status failed after $ATTEMPTS attempts"; fi
  # Simulate restart to verify auto-unseal on restart
  podman stop vault-target
  sleep 2
  "$SCRIPTS_DIR/vault" server > vault-restart.log 2>&1 &
  RESTART_PID=$!
  sleep 10
  SUCCESS=false
  for ((i=1; i<=$ATTEMPTS; i++)); do
    STATUS=$("$SCRIPTS_DIR/vault" status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Sealed.*false"; then
      echo "✅ Status after restart passed (auto-unsealed)"
      SUCCESS=true
      break
    fi
    sleep 1
  done
  if ! $SUCCESS; then echo "❌ Restart status failed after $ATTEMPTS attempts"; fi
  podman stop vault-target || true
  wait $RESTART_PID || true
  rm vault-restart.log
fi
# Clean up test server
podman stop vault-target || true
wait $SERVER_PID || true
rm vault-test.log
