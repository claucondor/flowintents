# FlowIntents — Solver Registration & Intent Guide

## Contract Addresses (Flow Mainnet)

| Contract | Network | Address |
|----------|---------|---------|
| AgentIdentityRegistry (ERC-8004) | Flow EVM | `0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223` |
| FlowIntentsComposerV2 | Flow EVM | `0x37c6F3A5F7C27274112eB903242cD9a82239F5B9` |
| EVMBidRelay | Flow EVM | `0x4fc88d2ed70D31303784C6963F245ee18e0d1784` |
| WFLOW | Flow EVM | `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` |
| stgUSDC | Flow EVM | `0xF1815bd50389c46847f0Bda824eC8da914045D14` |
| MORE Protocol Pool | Flow EVM | `0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d` |
| FlowIntents Cadence contracts | Cadence | `0xc65395858a38d8ff` |
| Flow EVM RPC | — | `https://mainnet.evm.nodes.onflow.org` (chainId 747) |

---

## Solver Registration

### Path A — Cadence Solver (full access, can execute strategies)

**Requirements:** Flow account with ~1 FLOW + EVM wallet

**Step 1 — Create COA** (Cadence Owned Account = your EVM address on Flow)
```bash
flow transactions send cadence/transactions/admin/createCOA.cdc \
  --signer <your-account> --network mainnet
```

Get your COA address:
```bash
# save as /tmp/coa.cdc
import EVM from 0xe467b9dd11fa00df
access(all) fun main(addr: Address): String {
    return getAccount(addr).capabilities
        .borrow<&EVM.CadenceOwnedAccount>(/public/evm)?.address().toString() ?? "no COA"
}
# flow scripts execute /tmp/coa.cdc --args-json '[{"type":"Address","value":"<your-address>"}]' --network mainnet
```

**Step 2 — Register in AgentIdentityRegistry (EVM)**
```bash
cast send 0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223 \
  "register()" \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key <your-evm-key>

# Get your tokenId:
cast call 0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223 \
  "getTokenByOwner(address)(uint256)" <your-evm-address> \
  --rpc-url https://mainnet.evm.nodes.onflow.org
```

**Step 3 — Register in SolverRegistryV0_1 (Cadence)**
```bash
flow transactions send cadence/transactions/registerSolverV0_2.cdc \
  --args-json '[{"type":"String","value":"<your-evm-address>"},{"type":"UInt256","value":"<tokenId>"}]' \
  --signer <your-account> --network mainnet
```

**Verify:**
```bash
# save as /tmp/check.cdc
import SolverRegistryV0_1 from 0xc65395858a38d8ff
access(all) fun main(addr: Address): Bool {
    return SolverRegistryV0_1.isRegistered(cadenceAddress: addr)
}
# flow scripts execute /tmp/check.cdc --args-json '[{"type":"Address","value":"<your-address>"}]' --network mainnet
# returns: true
```

---

### Path B — EVM-only Solver (MetaMask only, no Flow account)

**Requirements:** EVM wallet with some FLOW for gas

**Step 1 — Register in AgentIdentityRegistry (EVM)**
```bash
cast send 0xA60c41C1C177cB38bcCEE06Da5360eCcaFB40223 \
  "register()" \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key <your-evm-key>
```

**Step 2 — One-time relay into Cadence** (done by protocol relayer)

Until the proxy contract is deployed, a trusted relayer registers you:
```bash
flow transactions send cadence/transactions/registerEVMSolverRelay.cdc \
  --args-json '[{"type":"String","value":"<your-evm-address>"},{"type":"UInt256","value":"<tokenId>"}]' \
  --signer <relayer-account> --network mainnet
```

> ⚠️ **Limitation:** Each EVM solver needs a unique relayer account as proxy.
> This is resolved by the EVMSolverProxy contract (see below).

**Step 3 — Post bids from MetaMask**
```bash
cast send 0x4fc88d2ed70D31303784C6963F245ee18e0d1784 \
  "submitBid(uint256,uint256,uint256,bytes)" \
  <intentId> <offeredAPY_bps> <maxGasBid_attoflow> <encodedBatch_hex> \
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key <your-evm-key>
```

A Cadence relayer then calls `relayEVMBid.cdc` to forward into `BidManagerV0_2`.

---

### ⚠️ Pending: EVMSolverProxy contract

**Problem:** `SolverRegistryV0_1` requires a unique Cadence address per solver.
EVM-only solvers have no Cadence address — currently they borrow a relayer's address,
limiting each relayer to one EVM solver proxy.

**Solution (next sprint):** Deploy `EVMSolverProxy.cdc`:
- Generates a deterministic virtual Cadence address per EVM solver
- Single contract handles unlimited EVM-only solvers
- No individual Cadence accounts needed

---

### Registered Solvers (Mainnet)

| | Type | Cadence Address | EVM Address | ERC-8004 tokenId |
|-|------|-----------------|-------------|-----------------|
| Solver A | Cadence | `0xc65395858a38d8ff` | `0xA0cD6ffcb6577...Bcda3` | 1 |
| Solver B | EVM-only | pending proxy | `0x1e237D7E2eaF...1D47` | 2 |

---

## Creating Intents

### From EVM side (works today ✅)

User deposits FLOW directly into `FlowIntentsComposerV2` — principal lives on EVM,
execution is fully on-chain without any cross-VM bridge needed.

```bash
# Swap intent: deposit 1 FLOW, want it wrapped to WFLOW
cast send 0x37c6F3A5F7C27274112eB903242cD9a82239F5B9 \
  "submitIntent(address,uint256,uint256,uint256,uint8)" \
  0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e \  # token = WFLOW (desired output)
  1000000000000000000 \                          # amount = 1 FLOW
  500 \                                          # targetAPY = 5%
  7 \                                            # durationDays = 7
  0 \                                            # principalSide = 0 (EVM)
  --value 1000000000000000000 \                  # send 1 FLOW with the tx
  --rpc-url https://mainnet.evm.nodes.onflow.org \
  --private-key <your-evm-key>
```

The intent gets a numeric ID. The `ScheduledManagerV0_3` then mirrors it into Cadence
so solvers can see and bid on it from either side.

### From Cadence side (bridge implementation pending 🔧)

```bash
flow transactions send cadence/transactions/createIntentV0_3.cdc \
  --args-json '[
    {"type":"UFix64","value":"1.0"},
    {"type":"UFix64","value":"0.05"},
    {"type":"UFix64","value":"5.0"},
    {"type":"UInt64","value":"7"},
    {"type":"UFix64","value":"0.1"}
  ]' \
  --signer <your-account> --network mainnet
```

> **Gap (implementing tomorrow):** When `executeIntentV0_3` runs, it needs to bridge
> the principal FLOW from the Cadence vault to EVM before calling the strategy.
> Current plan:
> ```
> IntentExecutorV0_3.executeIntentV2()
>   → withdraw principal from IntentMarketplaceV0_3 vault
>   → coa.deposit(from: flowVault)          ← bridge Cadence FLOW → EVM balance
>   → coa.call(composerV2, encodedBatch)    ← execute strategy (already implemented)
> ```
> This makes Cadence-side intents fully equivalent to EVM-side intents.
> Commit target: before hackathon demo.

---

## Strategy Examples

### WFLOW Wrap (FLOW → WFLOW)

encodedBatch for 1 FLOW:
```
0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000 d3bf53dac106a0290b0483ecbc89d40fcc961f3e000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000004d0e30db000000000000000000000000000000000000000000000000000000000
```

Rebuild for any amount:
```bash
cd evm && forge script script/BuildWFLOWStrategy.s.sol:BuildWFLOWStrategy -vvv
```

### MORE Protocol Deposit (FLOW → WFLOW → MORE)

```bash
cd evm && forge script script/BuildMOREDepositStrategy.s.sol:BuildMOREDepositStrategy -vvv
```
