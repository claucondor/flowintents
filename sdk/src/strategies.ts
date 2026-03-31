/**
 * strategies.ts — Pure functions for encoding EVM strategy batches.
 *
 * Each function builds an ABI-encoded StrategyStep[] (the "encodedBatch" field)
 * that FlowIntentsComposerV4 accepts.
 *
 * The StrategyStep struct (from FlowIntentsComposerV4.sol):
 *   struct StrategyStep {
 *     uint8   protocol;   // 0=MORE, 1=STARGATE, 2=LAYERZERO, 3=WFLOW_WRAP, 4=CUSTOM, 5=ANKR_STAKE
 *     address target;     // contract to call
 *     bytes   callData;   // encoded call
 *     uint256 value;      // native FLOW in attoFLOW
 *   }
 *
 * The batch is abi.encode(StrategyStep[]) — a dynamic array of tuples.
 *
 * Reference: evm/script/BuildWrapAndSwapStrategy.s.sol, BuildWFLOWStrategy.s.sol,
 *            BuildAnkrFlowStakeStrategy.s.sol
 */

import { encodeAbiParameters, parseAbiParameters, encodeFunctionData } from 'viem'
import { TOKENS } from './types'

// ─────────────────────────────────────────────
// ABI — StrategyStep tuple array
// ─────────────────────────────────────────────

/**
 * Solidity type: StrategyStep[] = (uint8 protocol, address target, bytes callData, uint256 value)[]
 *
 * This matches exactly the struct in FlowIntentsComposerV4.sol.
 */
const STRATEGY_STEP_ARRAY_ABI = parseAbiParameters(
  '(uint8 protocol, address target, bytes callData, uint256 value)[]',
)

// ─────────────────────────────────────────────
// Protocol IDs (from the Protocol enum in ComposerV4)
// ─────────────────────────────────────────────

export const PROTOCOL = {
  MORE: 0,
  STARGATE: 1,
  LAYERZERO: 2,
  WFLOW_WRAP: 3,
  CUSTOM: 4,
  ANKR_STAKE: 5,
} as const

// ─────────────────────────────────────────────
// Function selectors (hardcoded for gas efficiency)
// ─────────────────────────────────────────────

const SEL = {
  /** WFLOW.deposit() */
  WFLOW_DEPOSIT: '0xd0e30db0' as `0x${string}`,
  /** ERC20.approve(address,uint256) */
  ERC20_APPROVE: '0x095ea7b3' as `0x${string}`,
  /** IUniswapV2Router.swapExactTokensForTokens(uint256,uint256,address[],address,uint256) */
  SWAP_EXACT_TOKENS_FOR_TOKENS: '0x38ed1739' as `0x${string}`,
  /** Ankr FlowStakingPool.stakeCerts() */
  ANKR_STAKE_CERTS: '0xac76d450' as `0x${string}`,
}

// ─────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────

type Step = {
  protocol: number
  target: `0x${string}`
  callData: `0x${string}`
  value: bigint
}

/**
 * ABI-encode a StrategyStep[] into a hex string (0x-prefixed).
 * This is the exact format that FlowIntentsComposerV4.executeStrategyWithFunds() decodes.
 */
function encodeSteps(steps: Step[]): string {
  const encoded = encodeAbiParameters(STRATEGY_STEP_ARRAY_ABI, [
    steps.map((s) => ({
      protocol: s.protocol,
      target: s.target,
      callData: s.callData,
      value: s.value,
    })),
  ])
  return encoded  // already 0x-prefixed
}

/**
 * Converts a FLOW amount (float, in whole FLOW) to attoFLOW (bigint).
 * 1 FLOW = 1e18 attoFLOW.
 */
export function flowToAtto(flow: number): bigint {
  // Use 8 decimal places (matches Cadence UFix64 precision) to avoid
  // floating point rounding errors, then pad with 10 zeros for 18 decimals.
  const [whole, dec = ''] = flow.toFixed(8).split('.')
  const padded = dec.padEnd(8, '0').slice(0, 8) + '0000000000'
  return BigInt(whole + padded)
}

// ─────────────────────────────────────────────
// Public strategy encoders
// ─────────────────────────────────────────────

/**
 * Encode a single-step strategy that wraps native FLOW into WFLOW.
 *
 * Produces one StrategyStep:
 *   WFLOW.deposit{value: amountFlow}()
 *
 * The wrapped WFLOW stays in the ComposerV4 contract after execution.
 * ComposerV4.executeStrategyWithFunds() sweeps ERC-20 balances to `recipient`
 * after the batch runs — so WFLOW is automatically forwarded.
 *
 * @param amountFlow  Amount of FLOW to wrap, in whole FLOW (e.g. 1.0 = 1 FLOW).
 * @param recipient   EVM address that should receive the WFLOW (used as metadata;
 *                    actual sweeping is done by ComposerV4 after this batch).
 * @returns 0x-prefixed ABI-encoded StrategyStep[].
 */
export function encodeWrapFlowStrategy(amountFlow: number, _recipient: string): string {
  const steps: Step[] = [
    {
      protocol: PROTOCOL.WFLOW_WRAP,
      target: TOKENS.WFLOW as `0x${string}`,
      callData: SEL.WFLOW_DEPOSIT,
      value: flowToAtto(amountFlow),
    },
  ]
  return encodeSteps(steps)
}

/**
 * Encode a 3-step Wrap + Approve + Swap strategy.
 *
 * Steps:
 *   [0] WFLOW.deposit{value: amountFlow}()           — wrap all bridged FLOW to WFLOW
 *   [1] WFLOW.approve(ROUTER, swapAmount)             — approve router to spend swapAmount
 *   [2] ROUTER.swapExactTokensForTokens(              — swap swapAmount WFLOW -> outputToken
 *         swapAmount, minAmountOut, [WFLOW, outputToken], recipient, deadline
 *       )
 *
 * The remaining WFLOW (amountFlow - swapAmount) stays in ComposerV4 and is
 * swept to the recipient by executeStrategyWithFunds().
 *
 * Matches: evm/script/BuildWrapAndSwapStrategy.s.sol
 *
 * @param amountFlow    Total FLOW to wrap (whole FLOW, e.g. 0.2).
 * @param swapAmount    WFLOW amount to swap (whole FLOW, e.g. 0.1). Must be ≤ amountFlow.
 * @param outputToken   Address of the output token (e.g. TOKENS.stgUSDC).
 * @param recipient     EVM address that receives the swapped tokens.
 * @param minAmountOut  Minimum output amount (in output token's smallest unit, e.g. 2981 for stgUSDC).
 * @returns 0x-prefixed ABI-encoded StrategyStep[].
 */
export function encodeWrapAndSwapStrategy(
  amountFlow: number,
  swapAmount: number,
  outputToken: string,
  recipient: string,
  minAmountOut: bigint,
): string {
  const router = TOKENS.PUNCH_ROUTER as `0x${string}`
  const wflow = TOKENS.WFLOW as `0x${string}`
  const tokenOut = outputToken as `0x${string}`
  const to = recipient as `0x${string}`
  const swapAmountAtto = flowToAtto(swapAmount)

  // Far-future deadline (2100-01-01) — safe for long-lived encoded batches
  const deadline = 4102444800n

  // Step 1: WFLOW.approve(router, swapAmount)
  const approveCallData = encodeAbiParameters(
    parseAbiParameters('bytes4 selector, address spender, uint256 amount'),
    [SEL.ERC20_APPROVE, router, swapAmountAtto],
  )
  // encodeAbiParameters with selector prefix is not standard — use encodeFunctionData approach
  const approvePacked = (SEL.ERC20_APPROVE +
    encodeAbiParameters(parseAbiParameters('address, uint256'), [router, swapAmountAtto]).slice(2)
  ) as `0x${string}`

  // Step 2: ROUTER.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)
  const swapPacked = (SEL.SWAP_EXACT_TOKENS_FOR_TOKENS +
    encodeAbiParameters(
      parseAbiParameters('uint256, uint256, address[], address, uint256'),
      [swapAmountAtto, minAmountOut, [wflow, tokenOut], to, deadline],
    ).slice(2)
  ) as `0x${string}`

  // Step 4: Dummy call to outputToken so ComposerV5's sweep detects its balance.
  // balanceOf(address(0)) is a harmless read — it just makes the token a "target"
  // so the sweep loop finds and transfers the swapped tokens to the recipient.
  const dummyCallData = ('0x70a08231' +
    encodeAbiParameters(parseAbiParameters('address'), ['0x0000000000000000000000000000000000000000' as `0x${string}`]).slice(2)
  ) as `0x${string}`

  const steps: Step[] = [
    {
      protocol: PROTOCOL.CUSTOM,
      target: wflow,
      callData: SEL.WFLOW_DEPOSIT,
      value: flowToAtto(amountFlow),
    },
    {
      protocol: PROTOCOL.CUSTOM,
      target: wflow,
      callData: approvePacked,
      value: 0n,
    },
    {
      protocol: PROTOCOL.CUSTOM,
      target: router,
      callData: swapPacked,
      value: 0n,
    },
    {
      protocol: PROTOCOL.CUSTOM,
      target: tokenOut,
      callData: dummyCallData,
      value: 0n,
    },
  ]

  return encodeSteps(steps)
}

/**
 * Encode a single-step ANKR staking strategy.
 *
 * Produces one StrategyStep:
 *   AnkrFlowStakingPool.stakeCerts{value: amountFlow}()
 *
 * The aFLOWEVMb certificate token received is swept to recipient by ComposerV4.
 *
 * NOTE: stakeBonds() is PAUSED on mainnet — always use stakeCerts().
 *
 * Matches: evm/script/BuildAnkrFlowStakeStrategy.s.sol
 *
 * @param amountFlow  Amount of FLOW to stake (whole FLOW, e.g. 0.5).
 * @param _recipient  EVM address for reference (actual sweep handled by ComposerV4).
 * @returns 0x-prefixed ABI-encoded StrategyStep[].
 */
export function encodeANKRStakeStrategy(amountFlow: number, _recipient: string): string {
  // Dummy call to cert token so ComposerV5 sweep detects the output
  const dummyCallData = ('0x70a08231' +
    encodeAbiParameters(parseAbiParameters('address'), ['0x0000000000000000000000000000000000000000' as `0x${string}`]).slice(2)
  ) as `0x${string}`

  const steps: Step[] = [
    {
      protocol: PROTOCOL.ANKR_STAKE,
      target: TOKENS.ANKR_STAKING_POOL as `0x${string}`,
      callData: SEL.ANKR_STAKE_CERTS,
      value: flowToAtto(amountFlow),
    },
    {
      protocol: PROTOCOL.CUSTOM,
      target: TOKENS.ANKR_CERT_TOKEN as `0x${string}`,
      callData: dummyCallData,
      value: 0n,
    },
  ]
  return encodeSteps(steps)
}

/**
 * Encode a custom strategy from raw StrategyStep-like inputs.
 *
 * Useful when you have a pre-computed callData and need to wrap it
 * in the correct ABI encoding for ComposerV4.
 *
 * @param steps  Array of raw step descriptors.
 * @returns 0x-prefixed ABI-encoded StrategyStep[].
 */
export function encodeCustomStrategy(
  steps: Array<{
    protocol?: number
    target: string
    callData: string
    value: number | bigint
  }>,
): string {
  const typedSteps: Step[] = steps.map((s) => ({
    protocol: s.protocol ?? PROTOCOL.CUSTOM,
    target: s.target as `0x${string}`,
    callData: s.callData as `0x${string}`,
    value: typeof s.value === 'bigint' ? s.value : flowToAtto(s.value as number),
  }))
  return encodeSteps(typedSteps)
}

// Suppress unused import warning for encodeFunctionData (kept for potential future use)
void encodeFunctionData
