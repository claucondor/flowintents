#!/bin/bash
# deploy-v0_2-mainnet.sh
# Deploy / update V0_2 Cadence contracts on Flow mainnet.
# Run from repo root: DEPLOYER_PRIVATE_KEY=<key> ./scripts/deploy-v0_2-mainnet.sh

set -e

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
  echo "ERROR: DEPLOYER_PRIVATE_KEY not set"
  exit 1
fi

NETWORK=mainnet

echo "=== FlowIntents V0_2 Mainnet Deploy ==="
echo "Account: 0xc65395858a38d8ff"
echo "Network: $NETWORK"
echo ""

# --- 1. Add BidManagerV0_2 (new contract, not yet on mainnet) ---
echo "[1/4] Adding BidManagerV0_2..."
flow accounts add-contract cadence/contracts/BidManagerV0_2.cdc \
  --signer mainnet-account \
  --network $NETWORK

# --- 2. Update IntentMarketplaceV0_2 ---
echo "[2/4] Updating IntentMarketplaceV0_2..."
flow accounts update-contract cadence/contracts/IntentMarketplaceV0_2.cdc \
  --signer mainnet-account \
  --network $NETWORK

# --- 3. Update IntentExecutorV0_2 ---
echo "[3/4] Updating IntentExecutorV0_2..."
flow accounts update-contract cadence/contracts/IntentExecutorV0_2.cdc \
  --signer mainnet-account \
  --network $NETWORK

# --- 4. Update ScheduledManagerV0_2 ---
echo "[4/4] Updating ScheduledManagerV0_2..."
flow accounts update-contract cadence/contracts/ScheduledManagerV0_2.cdc \
  --signer mainnet-account \
  --network $NETWORK

echo ""
echo "=== V0_2 Deploy Complete ==="
echo ""
echo "Next steps (admin transactions):"
echo "  flow transactions send cadence/transactions/admin/setExecutorV0_2ComposerAddress.cdc \\"
echo "    <FlowIntentsComposerV2_address> --signer mainnet-account --network mainnet"
