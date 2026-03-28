/**
 * tools.ts — Tool definitions and implementations for the Claude solver agent.
 *
 * Claude uses these tools to:
 * 1. Query DEX/protocol rates (PunchSwap quote, Ankr/MORE APY)
 * 2. Encode on-chain strategy batches (swap, yield)
 *
 * All EVM calls use viem's readContract via public RPC.
 */

import Anthropic from "@anthropic-ai/sdk";
import { createPublicClient, http, encodeFunctionData, encodeAbiParameters } from "viem";
import { EVM_ADDRESSES, SELECTORS, PROTOCOL_ID } from "./config.js";

// ─── Flow EVM public client (chainId 747) ─────────────────────────────────────

const FLOW_EVM_RPC = "https://mainnet.evm.nodes.onflow.org";

const publicClient = createPublicClient({
  transport: http(FLOW_EVM_RPC),
  chain: {
    id: 747,
    name: "Flow EVM Mainnet",
    nativeCurrency: { name: "Flow", symbol: "FLOW", decimals: 18 },
    rpcUrls: { default: { http: [FLOW_EVM_RPC] } },
  },
});

// ─── Minimal ABIs ─────────────────────────────────────────────────────────────

const PUNCHSWAP_ROUTER_ABI = [
  {
    name: "getAmountsOut",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "amountIn", type: "uint256" },
      { name: "path", type: "address[]" },
    ],
    outputs: [{ name: "amounts", type: "uint256[]" }],
  },
] as const;

// ─── StrategyStep type (mirrors the Solidity struct) ──────────────────────────

interface StrategyStep {
  protocol: number;   // PROTOCOL_ID values
  target: `0x${string}`;
  callData: `0x${string}`;
  value: bigint;      // attoFLOW (non-zero only for native-value steps)
}

// ─── Tool implementations ─────────────────────────────────────────────────────

/**
 * Get a quote from PunchSwap for swapping WFLOW to a target token.
 * Returns the estimated output amount (in smallest token units).
 * Falls back to a simulated value if the RPC call fails.
 */
export async function getPunchSwapQuote(
  amountInFlow: number,
  tokenOut: string
): Promise<number> {
  try {
    const amountInWei = BigInt(Math.floor(amountInFlow * 1e18));
    const path = [EVM_ADDRESSES.WFLOW, tokenOut as `0x${string}`];

    const amounts = await publicClient.readContract({
      address: EVM_ADDRESSES.PUNCHSWAP_ROUTER as `0x${string}`,
      abi: PUNCHSWAP_ROUTER_ABI,
      functionName: "getAmountsOut",
      args: [amountInWei, path],
    }) as bigint[];

    // amounts[1] is the estimated output
    const out = amounts[1];
    // Return as a human-readable number (keeping raw units for token — caller interprets)
    return Number(out);
  } catch (err) {
    console.warn(
      `  [tools] PunchSwap RPC call failed, using simulated quote: ${err}`
    );
    // Simulated: ~3191 stgUSDC units (6-decimal) per 0.1 WFLOW
    // (observed in E2E tests: 0.1 WFLOW → ~3191 stgUSDC)
    const simulatedRate = 31910; // stgUSDC units per WFLOW
    return Math.floor(amountInFlow * simulatedRate);
  }
}

/**
 * Get current APY for Ankr liquid staking on Flow EVM.
 * Mocked at realistic current value (complex on-chain oracle needed for live data).
 */
export async function getAnkrAPY(): Promise<number> {
  // aFLOWEVMb staking APY — realistic mainnet value as of early 2026
  return 4.2;
}

/**
 * Get current APY for depositing WFLOW in MORE Finance (Aave v3 fork).
 * Mocked at realistic current value.
 */
export async function getMOREFinanceAPY(): Promise<number> {
  // WFLOW lending APY on MORE Finance — realistic mainnet value
  return 3.8;
}

/**
 * Encode an EVM batch strategy for a FLOW -> WFLOW -> token swap.
 *
 * Steps:
 *   [0] WFLOW.deposit{value: wrapAmount}()
 *   [1] WFLOW.approve(router, swapAmount)
 *   [2] router.swapExactTokensForTokens(swapAmount, minAmountOut, [WFLOW, tokenOut], recipient, deadline)
 *
 * Returns the hex-encoded batch bytes (to be passed to submitBidV0_3 as encodedBatch).
 */
export function encodeSwapStrategy(params: {
  wrapAmount: number;
  swapAmount: number;
  tokenOut: string;
  recipient: string;
  minAmountOut: number;
}): string {
  const wrapWei = BigInt(Math.floor(params.wrapAmount * 1e18));
  const swapWei = BigInt(Math.floor(params.swapAmount * 1e18));
  const minOutBig = BigInt(Math.floor(params.minAmountOut));
  // Far-future deadline (year 2100) to avoid expiry issues
  const deadline = BigInt(4102444800);

  const steps: StrategyStep[] = [
    // Step 0: wrap FLOW → WFLOW
    {
      protocol: PROTOCOL_ID.CUSTOM,
      target: EVM_ADDRESSES.WFLOW as `0x${string}`,
      callData: SELECTORS.WFLOW_DEPOSIT as `0x${string}`,
      value: wrapWei,
    },
    // Step 1: approve router to spend WFLOW
    {
      protocol: PROTOCOL_ID.CUSTOM,
      target: EVM_ADDRESSES.WFLOW as `0x${string}`,
      callData: encodeFunctionData({
        abi: [{ name: "approve", type: "function", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ name: "", type: "bool" }] }],
        functionName: "approve",
        args: [EVM_ADDRESSES.PUNCHSWAP_ROUTER as `0x${string}`, swapWei],
      }),
      value: 0n,
    },
    // Step 2: swap WFLOW → tokenOut
    {
      protocol: PROTOCOL_ID.CUSTOM,
      target: EVM_ADDRESSES.PUNCHSWAP_ROUTER as `0x${string}`,
      callData: encodeFunctionData({
        abi: [{
          name: "swapExactTokensForTokens",
          type: "function",
          inputs: [
            { name: "amountIn", type: "uint256" },
            { name: "amountOutMin", type: "uint256" },
            { name: "path", type: "address[]" },
            { name: "to", type: "address" },
            { name: "deadline", type: "uint256" },
          ],
          outputs: [{ name: "amounts", type: "uint256[]" }],
        }],
        functionName: "swapExactTokensForTokens",
        args: [
          swapWei,
          minOutBig,
          [EVM_ADDRESSES.WFLOW as `0x${string}`, params.tokenOut as `0x${string}`],
          params.recipient as `0x${string}`,
          deadline,
        ],
      }),
      value: 0n,
    },
  ];

  return encodeStrategySteps(steps);
}

/**
 * Encode a yield strategy batch for MORE Finance (deposit WFLOW) or Ankr (stake FLOW).
 *
 * MORE steps:
 *   [0] WFLOW.approve(morePool, amount)
 *   [1] morePool.deposit(WFLOW, amount, recipient, 0)
 *
 * Ankr steps:
 *   [0] stakingPool.stakeCerts{value: amount}()
 */
export function encodeYieldStrategy(params: {
  protocol: "more" | "ankr";
  amount: number;
  recipient: string;
}): string {
  const amountWei = BigInt(Math.floor(params.amount * 1e18));

  let steps: StrategyStep[];

  if (params.protocol === "more") {
    steps = [
      // Step 0: approve MORE pool to spend WFLOW
      {
        protocol: PROTOCOL_ID.CUSTOM,
        target: EVM_ADDRESSES.WFLOW as `0x${string}`,
        callData: encodeFunctionData({
          abi: [{ name: "approve", type: "function", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ name: "", type: "bool" }] }],
          functionName: "approve",
          args: [EVM_ADDRESSES.MORE_POOL as `0x${string}`, amountWei],
        }),
        value: 0n,
      },
      // Step 1: deposit WFLOW into MORE (Aave v2 interface)
      {
        protocol: PROTOCOL_ID.MORE,
        target: EVM_ADDRESSES.MORE_POOL as `0x${string}`,
        callData: encodeFunctionData({
          abi: [{
            name: "deposit",
            type: "function",
            inputs: [
              { name: "asset", type: "address" },
              { name: "amount", type: "uint256" },
              { name: "onBehalfOf", type: "address" },
              { name: "referralCode", type: "uint16" },
            ],
            outputs: [],
          }],
          functionName: "deposit",
          args: [
            EVM_ADDRESSES.WFLOW as `0x${string}`,
            amountWei,
            params.recipient as `0x${string}`,
            0,
          ],
        }),
        value: 0n,
      },
    ];
  } else {
    // Ankr: stakeCerts() is payable — send FLOW directly
    steps = [
      {
        protocol: PROTOCOL_ID.ANKR_STAKE,
        target: EVM_ADDRESSES.ANKR_STAKING_POOL as `0x${string}`,
        callData: SELECTORS.ANKR_STAKE_CERTS as `0x${string}`,
        value: amountWei,
      },
    ];
  }

  return encodeStrategySteps(steps);
}

/**
 * ABI-encode an array of StrategyStep structs.
 * Mirrors the Solidity: abi.encode(steps) where steps is StrategyStep[].
 */
function encodeStrategySteps(steps: StrategyStep[]): string {
  // StrategyStep tuple: (uint8 protocol, address target, bytes callData, uint256 value)
  const abiType = [
    {
      type: "tuple[]",
      components: [
        { name: "protocol", type: "uint8" },
        { name: "target", type: "address" },
        { name: "callData", type: "bytes" },
        { name: "value", type: "uint256" },
      ],
    },
  ] as const;

  const encoded = encodeAbiParameters(abiType, [
    steps.map((s) => ({
      protocol: s.protocol,
      target: s.target,
      callData: s.callData,
      value: s.value,
    })),
  ]);
  return encoded;
}

// ─── Tool Definitions for Claude ─────────────────────────────────────────────

export const CLAUDE_TOOLS: Anthropic.Tool[] = [
  {
    name: "get_punchswap_quote",
    description:
      "Get a quote from PunchSwap DEX for swapping WFLOW to a target token on Flow EVM. Returns the estimated output amount in raw token units.",
    input_schema: {
      type: "object" as const,
      properties: {
        amountIn: {
          type: "number",
          description: "Amount of WFLOW to swap (e.g. 0.1 means 0.1 WFLOW)",
        },
        tokenOut: {
          type: "string",
          description:
            "Output token contract address on Flow EVM (e.g. 0xF1815bd50389c46847f0Bda824eC8da914045D14 for stgUSDC)",
        },
      },
      required: ["amountIn", "tokenOut"],
    },
  },
  {
    name: "get_ankr_apy",
    description:
      "Get current APY (%) for liquid-staking FLOW with Ankr protocol on Flow EVM. Returns a percentage like 4.2 meaning 4.2% APY.",
    input_schema: {
      type: "object" as const,
      properties: {},
    },
  },
  {
    name: "get_more_finance_apy",
    description:
      "Get current APY (%) for depositing WFLOW in MORE Finance (Aave v3 fork) on Flow EVM. Returns a percentage like 3.8 meaning 3.8% APY.",
    input_schema: {
      type: "object" as const,
      properties: {},
    },
  },
  {
    name: "encode_swap_strategy",
    description:
      "Encode the EVM batch strategy for a FLOW → WFLOW → token swap via PunchSwap. Returns ABI-encoded bytes (hex string) for the encodedBatch field in submitBidV0_3.",
    input_schema: {
      type: "object" as const,
      properties: {
        wrapAmount: {
          type: "number",
          description: "Total FLOW to wrap to WFLOW (e.g. 0.2)",
        },
        swapAmount: {
          type: "number",
          description: "WFLOW amount to swap via PunchSwap (e.g. 0.1)",
        },
        tokenOut: {
          type: "string",
          description: "Output token address on Flow EVM",
        },
        recipient: {
          type: "string",
          description:
            "EVM address that will receive the output tokens (0x-prefixed)",
        },
        minAmountOut: {
          type: "number",
          description:
            "Minimum acceptable output amount in raw token units (use 95% of the quoted amount for slippage protection)",
        },
      },
      required: ["wrapAmount", "swapAmount", "tokenOut", "recipient", "minAmountOut"],
    },
  },
  {
    name: "encode_yield_strategy",
    description:
      "Encode the EVM batch strategy for a yield intent — either depositing WFLOW into MORE Finance or staking FLOW with Ankr. Returns ABI-encoded bytes (hex string) for encodedBatch.",
    input_schema: {
      type: "object" as const,
      properties: {
        protocol: {
          type: "string",
          enum: ["more", "ankr"],
          description:
            "'more' to deposit WFLOW into MORE Finance (Aave v3), 'ankr' to stake FLOW and receive aFLOWEVMb cert tokens",
        },
        amount: {
          type: "number",
          description: "FLOW/WFLOW amount to deposit/stake",
        },
        recipient: {
          type: "string",
          description:
            "EVM address that will receive yield tokens (mFlowWFLOW or aFLOWEVMb)",
        },
      },
      required: ["protocol", "amount", "recipient"],
    },
  },
];

// ─── Tool dispatcher ──────────────────────────────────────────────────────────

export interface ToolInput {
  amountIn?: number;
  tokenOut?: string;
  wrapAmount?: number;
  swapAmount?: number;
  recipient?: string;
  minAmountOut?: number;
  protocol?: "more" | "ankr";
  amount?: number;
}

export async function executeTool(
  toolName: string,
  toolInput: ToolInput
): Promise<string> {
  switch (toolName) {
    case "get_punchswap_quote": {
      const amountIn = toolInput.amountIn ?? 0.1;
      const tokenOut = toolInput.tokenOut ?? EVM_ADDRESSES.STG_USDC;
      const quote = await getPunchSwapQuote(amountIn, tokenOut);
      return JSON.stringify({
        amountIn,
        tokenOut,
        estimatedOut: quote,
        note:
          tokenOut === EVM_ADDRESSES.STG_USDC
            ? "stgUSDC has 6 decimals — divide by 1e6 for human-readable value"
            : "Check token decimals to interpret the raw output amount",
      });
    }

    case "get_ankr_apy": {
      const apy = await getAnkrAPY();
      return JSON.stringify({ protocol: "Ankr", apy, unit: "% per year" });
    }

    case "get_more_finance_apy": {
      const apy = await getMOREFinanceAPY();
      return JSON.stringify({ protocol: "MORE Finance", apy, unit: "% per year" });
    }

    case "encode_swap_strategy": {
      const encoded = encodeSwapStrategy({
        wrapAmount: toolInput.wrapAmount ?? 0.2,
        swapAmount: toolInput.swapAmount ?? 0.1,
        tokenOut: toolInput.tokenOut ?? EVM_ADDRESSES.STG_USDC,
        recipient: toolInput.recipient ?? "0x0000000000000000000000000000000000000000",
        minAmountOut: toolInput.minAmountOut ?? 0,
      });
      return JSON.stringify({
        strategy: "swap",
        encodedBatch: encoded,
        stepsCount: 3,
        note: "Pass encodedBatch to submitBidV0_3 as the encodedBatch argument",
      });
    }

    case "encode_yield_strategy": {
      const proto = toolInput.protocol ?? "more";
      const encoded = encodeYieldStrategy({
        protocol: proto,
        amount: toolInput.amount ?? 1.0,
        recipient: toolInput.recipient ?? "0x0000000000000000000000000000000000000000",
      });
      return JSON.stringify({
        strategy: `yield-${proto}`,
        encodedBatch: encoded,
        stepsCount: proto === "more" ? 2 : 1,
        note: "Pass encodedBatch to submitBidV0_3 as the encodedBatch argument",
      });
    }

    default:
      return JSON.stringify({ error: `Unknown tool: ${toolName}` });
  }
}
