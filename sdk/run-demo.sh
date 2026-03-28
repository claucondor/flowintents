#!/usr/bin/env bash
# run-demo.sh — Run both solver bots in parallel for the FlowIntents demo.
#
# Prerequisites:
#   - Node.js >= 18
#   - npm install (already done in sdk/)
#   - Set environment variables below OR export them before running
#
# Usage:
#   bash sdk/run-demo.sh
#
# Stop both bots:
#   Ctrl+C  (kills both background processes)

set -e

# ── Bot A credentials (Aggressive) ────────────────────────────────────────────
# export SOLVER_PK="your_bot_a_private_key_hex"
# export SOLVER_ADDRESS="0xYourBotACadenceAddress"
# export SOLVER_EVM_ADDRESS="0xYourBotAEvmAddress"  # optional

# ── Bot B credentials (Conservative) ─────────────────────────────────────────
# export SOLVER_PK_B="your_bot_b_private_key_hex"
# export SOLVER_ADDRESS_B="0xYourBotBCadenceAddress"
# export SOLVER_EVM_ADDRESS_B="0xYourBotBEvmAddress"  # optional

# ── Validate required env vars ────────────────────────────────────────────────

if [ -z "$SOLVER_PK" ] || [ -z "$SOLVER_ADDRESS" ]; then
  echo ""
  echo "  ERROR: Bot A credentials not set."
  echo ""
  echo "  Required:"
  echo "    export SOLVER_PK=<hex_private_key>          # Bot A Flow Cadence key"
  echo "    export SOLVER_ADDRESS=0x...                 # Bot A Flow Cadence address"
  echo ""
  echo "  Optional (for Bot B):"
  echo "    export SOLVER_PK_B=<hex_private_key>        # Bot B Flow Cadence key"
  echo "    export SOLVER_ADDRESS_B=0x...               # Bot B Flow Cadence address"
  echo ""
  echo "  If SOLVER_PK_B / SOLVER_ADDRESS_B are not set, only Bot A runs."
  echo ""
  exit 1
fi

# ── Navigate to sdk directory ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Install deps if needed ────────────────────────────────────────────────────

if [ ! -d "node_modules" ]; then
  echo "[run-demo] Installing dependencies..."
  npm install
fi

# ── Trap to kill background jobs on exit ─────────────────────────────────────

cleanup() {
  echo ""
  echo "[run-demo] Shutting down solver bots..."
  kill "$BOT_A_PID" 2>/dev/null || true
  kill "$BOT_B_PID" 2>/dev/null || true
  wait 2>/dev/null
  echo "[run-demo] Done."
}
trap cleanup EXIT INT TERM

# ── Launch Bot A ──────────────────────────────────────────────────────────────

echo ""
echo "  Starting Bot A (Aggressive)..."
npx ts-node --skipProject --compiler-options '{"module":"commonjs","esModuleInterop":true}' \
  solver-bot-a.ts &
BOT_A_PID=$!

# ── Launch Bot B (if credentials present) ────────────────────────────────────

if [ -n "$SOLVER_PK_B" ] && [ -n "$SOLVER_ADDRESS_B" ]; then
  echo "  Starting Bot B (Conservative)..."
  npx ts-node --skipProject --compiler-options '{"module":"commonjs","esModuleInterop":true}' \
    solver-bot-b.ts &
  BOT_B_PID=$!
  echo ""
  echo "  Both bots running. Press Ctrl+C to stop."
  echo ""
else
  echo ""
  echo "  Bot A running (Bot B credentials not set — single-bot demo mode)."
  echo "  Press Ctrl+C to stop."
  echo ""
fi

# ── Wait ──────────────────────────────────────────────────────────────────────

wait
