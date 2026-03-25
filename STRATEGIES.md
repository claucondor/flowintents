# FlowIntents Solver Strategy Guide

**Chain:** Flow EVM mainnet (chainId 747)
**RPC:** `https://mainnet.evm.nodes.onflow.org`
**Composer:** FlowIntentsComposerV4 @ `0xe02fE15f26A3B49cfdd8De16A1352aCFf0F880e1`

This document describes verified solver strategies for FlowIntents on Flow EVM mainnet.
All contracts and function selectors have been confirmed live via `cast call` probes.

---

## Key Principle

**Solvers decide the strategy. The protocol executes whatever batch you propose.**

An `encodedBatch` is `abi.encode(StrategyStep[])` where:

```solidity
struct StrategyStep {
    uint8   protocol;  // arbitrary label (see below)
    address target;    // contract to call
    bytes   callData;  // ABI-encoded function call
    uint256 value;     // attoFLOW to send with the call (0 for ERC-20)
}
```

Protocol labels used in this repo:
| Value | Meaning     |
|-------|-------------|
| 0     | MORE        |
| 3     | WFLOW_WRAP  |
| 4     | CUSTOM      |
| 5     | ANKR_STAKE  |

---

## Verified Contracts

| Contract          | Address                                      | Confirmed |
|-------------------|----------------------------------------------|-----------|
| WFLOW             | `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` | name()="Wrapped Flow", deposit()=0xd0e30db0 |
| stgUSDC           | `0xF1815bd50389c46847f0Bda824eC8da914045D14` | name()="Bridged USDC (Stargate)", decimals=6 |
| USDC.e            | `0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52` | symbol()="USDC.e", decimals=6 |
| ankrFLOWEVM       | `0x1b97100eA1D7126C4d60027e231EA4CB25314bdb` | bond token (impl: CertificateToken) |
| aFLOWEVMb         | `0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A` | cert token from stakeCerts() |
| MORE Pool         | `0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d` | Aave v3, ADDRESSES_PROVIDER confirmed |
| mFlowWFLOW        | `0x02BF4bd075c1b7C8D85F54777eaAA3638135c059` | aToken output from MORE deposit |
| FlowStakingPool   | `0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a` | Ankr proxy (impl: FlowStakingPool) |
| PunchSwap Router  | `0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d` | PunchSwapV2Router02, 354k+ txns |
| PunchSwap Factory | `0x29372c22459a4e373851798bFd6808e71EA34A71` | PunchSwapV2Factory, 123 pairs |
| LayerZero EpV2    | `0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa` | eid=30336 |

---

## Strategy 1: FLOW -> WFLOW (Wrap)

**File:** `evm/script/BuildWFLOWStrategy.s.sol`
**Steps:** 1
**Protocol:** WFLOW is a standard WETH9 contract. `deposit()` is payable, no args.

```
[0] WFLOW_WRAP  target=WFLOW  callData=0xd0e30db0  value=<intent amount>
```

**Key facts:**
- Selector `0xd0e30db0` = `deposit()`
- Send FLOW as `value`, receive WFLOW 1:1
- totalSupply at probe time: ~113,948 WFLOW

**encodedBatch for 0.5 FLOW (example):**
```
forge script evm/script/BuildWFLOWStrategy.s.sol:BuildWFLOWStrategy -vvv
```
Output at 1 FLOW (from script run):
```
0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000d3bf53dac106a0290b0483ecbc89d40fcc961f3e00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000004d0e30db000000000000000000000000000000000000000000000000000000000
```

---

## Strategy 2: WFLOW -> mFlowWFLOW (MORE Protocol Yield)

**File:** `evm/script/BuildMOREDepositStrategy.s.sol`
**Steps:** 2 (approve + supply)
**Protocol:** MORE is an Aave v3 fork. Use `supply()` selector.

```
[0] CUSTOM  target=WFLOW      callData=approve(MORE_POOL, amount)      value=0
[1] MORE    target=MORE_POOL  callData=supply(WFLOW, amount, to, 0)    value=0
```

**Key facts:**
- MORE Protocol verified as Aave v3 via `ADDRESSES_PROVIDER()` = `0x1830a96466d1d108935865c75B0a9548681Cfd9A`
- Both `supply()` (0x617ba037) and `deposit()` (0xe8eda9df) selectors are live — both return error code 26 (INVALID_AMOUNT) when called with amount=0
- Use `supply()` (0x617ba037) as canonical selector
- Output token: **mFlowWFLOW** @ `0x02BF4bd075c1b7C8D85F54777eaAA3638135c059`
  - name(): "More Flow WFLOW", symbol(): "mFlowWFLOW"
  - totalSupply at probe: ~77,407 mFlowWFLOW
- Reserves list also includes: ankrFLOWEVM, USDC.e, cbBTC, USDF, WETH, WBTC, PYUSD0, stgUSDC

**encodedBatch for 1 WFLOW (from script run):**
```
0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002...
```
Run `forge script evm/script/BuildMOREDepositStrategy.s.sol:BuildMOREDepositStrategy -vvv` for the full hex.

**Important:** This strategy requires WFLOW as input. Combine with Strategy 1 (wrap) if starting from native FLOW.

---

## Strategy 3: FLOW -> aFLOWEVMb (Ankr Liquid Staking)

**File:** `evm/script/BuildAnkrFlowStakeStrategy.s.sol`
**Steps:** 1
**Protocol:** Ankr FlowStakingPool proxy.

```
[0] ANKR_STAKE  target=STAKING_POOL  callData=0xac76d450 (stakeCerts())  value=<intent amount>
```

**Key facts:**
- FlowStakingPool proxy: `0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a`
  - Implementation: `FlowStakingPool` @ `0xD812aB5EB22425749a972450f5E5cb8BD82cb4e4`
  - Verified at evm.flowscan.io 2024-10-10
- `stakeBonds()` is **currently paused** — confirmed via revert: "LiquidTokenStakingPool: bond staking is paused"
- `stakeCerts()` (selector `0xac76d450`) is **active** — confirmed by reaching ERC20 mint (fails only when msg.sender=0x0)
- Output token: **aFLOWEVMb** = "Ankr Reward Earning FLOW EVM" @ `0xd6Fd021662B83bb1aAbC2006583A62Ad2Efb8d4A`
- Pool `getFreeBalance()` at probe: ~32,805 FLOW
- `getMinStake()` = 0 (no minimum stake requirement)
- `ratio()` on ankrFLOWEVM token = 876179840361012875 (~0.876 FLOW per share — you get fewer shares than FLOW staked, which is expected for a yield-bearing token)

**encodedBatch for 0.5 FLOW:**
```
0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000005000000000000000000000000fe8189a3016cb6a3668b8ccdac520ce572d4287a000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000006f05b59d3b200000000000000000000000000000000000000000000000000000000000000000004ac76d45000000000000000000000000000000000000000000000000000000000
```

---

## Strategy 4: WFLOW -> stgUSDC via PunchSwap V2

**File:** `evm/script/BuildPunchSwapStrategy.s.sol`
**Steps:** 2 (approve + swap)
**Protocol:** PunchSwap V2 (Uniswap V2 fork, 354k+ transactions on mainnet).

```
[0] CUSTOM  target=WFLOW   callData=approve(ROUTER, amountIn)                                value=0
[1] CUSTOM  target=ROUTER  callData=swapExactTokensForTokens(amountIn,minOut,path,to,dl)    value=0
```

**Key facts:**
- Router: `0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d` (PunchSwapV2Router02)
- Factory: `0x29372c22459a4e373851798bFd6808e71EA34A71` (PunchSwapV2Factory) — 123 pairs
- `WFLOW()` on router returns `0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e` (confirmed)
- `getAmountsOut()` is live and returning prices

**Active WFLOW pairs (confirmed via factory.getPair()):**

| Pair           | Address                                      | Reserves (approx at probe)     |
|----------------|----------------------------------------------|-------------------------------|
| WFLOW/stgUSDC  | `0x83F9D1170967d46dd40447e6e66E1a58d2601124` | 5.6 WFLOW / 174,609 stgUSDC  |
| WFLOW/USDC.e   | `0x4B07F2D19028A7fB7BF5E9258f9666a9673dA331` | 9,386 WFLOW / 303 USDC.e      |
| WFLOW/WETH     | `0x681A3c23E7704e5c90e45ABf800996145a8096fD` | 1.21e18 WETH / 77,652 WFLOW   |
| WFLOW/USDF     | `0x17e96496212d06Eb1Ff10C6f853669Cc9947A1e7` | (active)                      |
| WFLOW/ankrFLOW | `0x442aE0F33d66F617AF9106e797fc251B574aEdb3` | (active)                      |
| WFLOW/WBTC     | `0xAebc9efe5599D430Bc9045148992d3df50487ef2` | (active)                      |

**Live price quotes (from getAmountsOut at probe time):**
- 0.5 WFLOW -> **14,300 stgUSDC** (~$0.01430, stgUSDC has 6 decimals)
- 0.5 WFLOW -> **16,112 USDC.e** (~$0.01611, USDC.e has 6 decimals)

Note: WFLOW/stgUSDC has thin liquidity (~5.6 WFLOW). WFLOW/USDC.e pair has token0=USDC.e, token1=WFLOW.

**encodedBatch for 0.5 WFLOW -> stgUSDC:**
```
0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002...
```
Run `forge script evm/script/BuildPunchSwapStrategy.s.sol:BuildPunchSwapStrategy -vvv` for the full hex.

**Important slippage note:** The example script uses `minOut=0`. In production, set `minOut = getAmountsOut(...) * 97 / 100` (3% slippage tolerance) to avoid sandwich attacks.

---

## What Doesn't Work

| Protocol          | Attempted Functions              | Result |
|-------------------|----------------------------------|--------|
| ankrFLOW (bond)   | `stakeBonds()`                   | Reverts: "bond staking is paused" |
| ankrFLOW          | `minimumStake()`, `getMinStake()`| Reverts on token contract (0x1b97...) — call the pool (0xFE81...) instead |
| FlowStakingPool impl | `getMinStake()`, `getTokens()` | Uninitialized — always call via proxy (0xFE81...) |
| stgUSDC           | `token()`, `poolId()`, `router()`| Reverts — stgUSDC is a bridged token, not a Stargate pool contract |
| Increment Finance | Various router addresses          | No deployed code found on Flow EVM |
| LayerZero EpV2    | Direct yield/swap strategy       | This is a messaging endpoint only (eid=30336) |

---

## Building a Multi-Step Strategy

For a complete **FLOW -> WFLOW -> mFlowWFLOW** (liquid + yield) strategy, combine steps from Strategies 1 and 2:

```solidity
StrategyStep[] memory steps = new StrategyStep[](3);
// Step 0: wrap FLOW to WFLOW
steps[0] = StrategyStep({ protocol: 3, target: WFLOW, callData: abi.encodeWithSelector(0xd0e30db0), value: amount });
// Step 1: approve MORE pool to spend WFLOW
steps[1] = StrategyStep({ protocol: 4, target: WFLOW, callData: abi.encodeWithSelector(0x095ea7b3, MORE_POOL, amount), value: 0 });
// Step 2: supply WFLOW into MORE pool
steps[2] = StrategyStep({ protocol: 0, target: MORE_POOL, callData: abi.encodeWithSelector(0x617ba037, WFLOW, amount, receiver, uint16(0)), value: 0 });
bytes memory encodedBatch = abi.encode(steps);
```

---

## Quick Reference: Function Selectors

| Function Signature                                         | Selector   | Contract       |
|------------------------------------------------------------|------------|----------------|
| `deposit()`                                                | `0xd0e30db0` | WFLOW         |
| `approve(address,uint256)`                                 | `0x095ea7b3` | any ERC-20    |
| `supply(address,uint256,address,uint16)`                   | `0x617ba037` | MORE Pool     |
| `deposit(address,uint256,address,uint16)`                  | `0xe8eda9df` | MORE Pool (alt) |
| `stakeCerts()`                                             | `0xac76d450` | FlowStakingPool |
| `swapExactTokensForTokens(uint256,uint256,address[],address,uint256)` | `0x38ed1739` | PunchSwap Router |
| `swapExactETHForTokens(uint256,address[],address,uint256)` | `0x7ff36ab5` | PunchSwap Router |
| `getAmountsOut(uint256,address[])`                         | (view)     | PunchSwap Router |

---

## Rebuild Notes for Solvers

1. **Every `encodedBatch` is intent-specific** — `value`, `receiver`, and swap `deadline` must match the current intent.
2. **MORE deposit flow:** wrap FLOW to WFLOW first, then approve + supply. The Composer must hold WFLOW before calling supply().
3. **PunchSwap swap:** `deadline = block.timestamp + 1800` is typical; encode at bid time, not intent creation time.
4. **ankrFLOW staking:** single step, just call `stakeCerts()` with the FLOW value attached.
5. **Slippage:** Always set a non-zero `amountOutMin` in production PunchSwap calls.
6. **Reserves change:** run `cast call $ROUTER "getAmountsOut(...)"` at bid time to get a fresh price quote.
