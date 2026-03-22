#!/bin/bash
# deploy-v0_3-mainnet.sh
# Add V0_3 Cadence contracts on Flow mainnet as NEW contracts (add-contract, not update).
# V0_2 contracts could not be updated because they add new resource fields
# (gasEscrow, executionDeadlineBlock, executedBy) that Cadence prohibits updating.
# V0_3 contracts are fresh deployments that include these fields from the start.
# Run from repo root: DEPLOYER_PRIVATE_KEY=<key> ./scripts/deploy-v0_3-mainnet.sh

set -e

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
  echo "ERROR: DEPLOYER_PRIVATE_KEY not set"
  exit 1
fi

NETWORK=mainnet

echo "=== FlowIntents V0_3 Mainnet Deploy ==="
echo "Account: 0xc65395858a38d8ff"
echo "Network: $NETWORK"
echo ""
echo "Note: BidManagerV0_2 is already deployed on mainnet — skipping."
echo ""

# --- 1. Add IntentMarketplaceV0_3 (new contract) ---
echo "[1/3] Adding IntentMarketplaceV0_3..."
flow accounts add-contract cadence/contracts/IntentMarketplaceV0_3.cdc \
  --signer mainnet-account \
  --network $NETWORK

# --- 2. Add IntentExecutorV0_3 (new contract) ---
echo "[2/3] Adding IntentExecutorV0_3..."
flow accounts add-contract cadence/contracts/IntentExecutorV0_3.cdc \
  --signer mainnet-account \
  --network $NETWORK

# --- 3. Add ScheduledManagerV0_3 (new contract) ---
echo "[3/3] Adding ScheduledManagerV0_3..."
flow accounts add-contract cadence/contracts/ScheduledManagerV0_3.cdc \
  --signer mainnet-account \
  --network $NETWORK

echo ""
echo "=== V0_3 Deploy Complete ==="
echo ""
echo "Next steps (admin transactions):"
echo "  flow transactions send cadence/transactions/admin/setExecutorV0_3ComposerAddress.cdc \\"
echo "    <FlowIntentsComposer_address> --signer mainnet-account --network mainnet"
