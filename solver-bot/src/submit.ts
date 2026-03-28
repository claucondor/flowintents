/**
 * submit.ts — Submit solver bids to the FlowIntents protocol via Flow CLI.
 *
 * Each bid calls `submitBidV0_3.cdc` with the parameters Claude decided on.
 * In DRY_RUN mode, the command is logged but not executed.
 */

import { execSync } from "child_process";
import { BOT_CONFIG } from "./config.js";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface BidParams {
  intentID: number;

  // Exactly one of these should be set:
  offeredAPY?: number;        // for Yield intents (e.g. 4.2 → "4.20000000")
  offeredAmountOut?: number;  // for Swap intents (raw units, e.g. 3041 stgUSDC)

  estimatedFeeBPS?: number;   // optional (e.g. 30 = 0.3%)
  targetChain?: string;       // optional (e.g. "flow-evm")
  maxGasBid: number;          // FLOW gas escrow bid (e.g. 0.01)
  strategy: string;           // "swap" | "yield-more" | "yield-ankr"
  encodedBatch: string;       // hex-encoded ABI batch from encode_*_strategy tools
}

// ─── UFix64 formatter ─────────────────────────────────────────────────────────

function toUFix64(n: number): string {
  return n.toFixed(8);
}

// ─── Build the Flow CLI command ───────────────────────────────────────────────

function buildFlowCommand(params: BidParams): string {
  const {
    intentID,
    offeredAPY,
    offeredAmountOut,
    estimatedFeeBPS,
    targetChain,
    maxGasBid,
    strategy,
    encodedBatch,
  } = params;

  // Convert encodedBatch hex to comma-separated decimal bytes for Flow CLI
  // Flow CLI expects [UInt8] as a Cadence array literal: e.g. [1, 2, 3]
  const hexWithout0x = encodedBatch.startsWith("0x")
    ? encodedBatch.slice(2)
    : encodedBatch;
  const byteArray = Array.from(
    { length: hexWithout0x.length / 2 },
    (_, i) => parseInt(hexWithout0x.slice(i * 2, i * 2 + 2), 16)
  );
  const cadenceBytesArg = `[${byteArray.join(",")}]`;

  const apyArg = offeredAPY != null ? `"${toUFix64(offeredAPY)}"` : '""';
  const amountOutArg =
    offeredAmountOut != null ? `"${toUFix64(offeredAmountOut)}"` : '""';
  const feeBPSArg = estimatedFeeBPS != null ? `"${estimatedFeeBPS}"` : '""';
  const chainArg = targetChain != null ? `"${targetChain}"` : '""';

  // Build argument string for `flow transactions send`
  const args = [
    `"${intentID}"`,           // intentID: UInt64
    apyArg,                    // offeredAPY: UFix64?
    amountOutArg,              // offeredAmountOut: UFix64?
    feeBPSArg,                 // estimatedFeeBPS: UInt64?
    chainArg,                  // targetChain: String?
    `"${toUFix64(maxGasBid)}"`, // maxGasBid: UFix64
    `"${strategy}"`,           // strategy: String
    cadenceBytesArg,           // encodedBatch: [UInt8]
  ].join(" ");

  return (
    `cd ${BOT_CONFIG.REPO_ROOT} && ` +
    `flow transactions send cadence/transactions/submitBidV0_3.cdc ` +
    `${args} ` +
    `--network ${BOT_CONFIG.FLOW_NETWORK} ` +
    `--signer mainnet-account`
  );
}

// ─── Submit bid ───────────────────────────────────────────────────────────────

export function submitBid(params: BidParams): { success: boolean; output: string } {
  const cmd = buildFlowCommand(params);

  console.log(`\n  [submit] Flow CLI command:`);
  console.log(`  $ ${cmd.replace(`cd ${BOT_CONFIG.REPO_ROOT} && `, "")}`);

  if (BOT_CONFIG.DRY_RUN) {
    console.log(`  [submit] DRY_RUN=true — skipping actual submission`);
    return { success: true, output: "DRY_RUN: bid not submitted" };
  }

  try {
    const output = execSync(cmd, {
      cwd: BOT_CONFIG.REPO_ROOT,
      timeout: 60_000,
      encoding: "utf8",
    });
    console.log(`  [submit] Transaction submitted:\n${output}`);
    return { success: true, output };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`  [submit] Submission failed: ${message}`);
    return { success: false, output: message };
  }
}

// ─── In-memory bid tracker (avoid double-bidding) ────────────────────────────

const biddedIntents = new Set<number>();

export function alreadyBidOnIntent(intentId: number): boolean {
  return biddedIntents.has(intentId);
}

export function markBidSubmitted(intentId: number): void {
  biddedIntents.add(intentId);
}
