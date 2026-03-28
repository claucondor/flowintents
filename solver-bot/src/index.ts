/**
 * index.ts — Main polling loop for the FlowIntents LLM-powered solver bot.
 *
 * Flow:
 *   1. Poll FlowIntents mainnet for open intents (every POLL_INTERVAL_MS)
 *   2. For each new intent, call Claude with tools to reason about the best strategy
 *   3. Claude queries PunchSwap/Ankr/MORE Finance via tools
 *   4. Claude returns a bid recommendation
 *   5. Bot submits the bid via Flow CLI (or logs it in DRY_RUN mode)
 */

import Anthropic from "@anthropic-ai/sdk";
import { getOpenIntents, Intent } from "./chain.js";
import { CLAUDE_TOOLS, executeTool, ToolInput } from "./tools.js";
import { submitBid, alreadyBidOnIntent, markBidSubmitted, BidParams } from "./submit.js";
import { BOT_CONFIG, EVM_ADDRESSES } from "./config.js";

// ─── Claude client ────────────────────────────────────────────────────────────

const claude = new Anthropic();

// ─── System prompt ────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are an expert DeFi solver for the FlowIntents protocol on Flow blockchain.
Your job is to find the best strategy to fulfill user intents and submit competitive bids.

FlowIntents supports three intent types:
- YIELD: User wants to maximize APY on their FLOW. You compare Ankr (~4.2% APY) vs MORE Finance (~3.8% APY).
- SWAP: User wants to swap FLOW for another token at the best rate. Use PunchSwap DEX.
- BridgeYield: User wants yield across chains — treat as Yield for now.

Available protocols on Flow EVM:
- PunchSwap: UniswapV2 DEX. WFLOW/stgUSDC is the main liquid pair.
- Ankr: Liquid staking — stake FLOW, receive aFLOWEVMb cert tokens (~4.2% APY).
- MORE Finance: Aave v3 fork — deposit WFLOW, receive mFlowWFLOW yield tokens (~3.8% APY).

Key addresses:
- WFLOW: ${EVM_ADDRESSES.WFLOW}
- stgUSDC: ${EVM_ADDRESSES.STG_USDC}
- PunchSwap Router: ${EVM_ADDRESSES.PUNCHSWAP_ROUTER}

Your workflow for each intent:
1. Analyze the intent type and parameters
2. Use the available tools to research current rates/quotes
3. Choose the best strategy
4. Encode the strategy batch using the appropriate encode_* tool
5. Return a JSON bid recommendation

IMPORTANT: You MUST use the tools to research before deciding. Do not guess rates.
Be competitive: your bid score depends on offering the best APY or most tokens out.

After researching, return your final bid as a JSON object with this exact shape:
{
  "strategy": "swap" | "yield-more" | "yield-ankr",
  "offeredAPY": <number or null>,
  "offeredAmountOut": <number or null>,
  "estimatedFeeBPS": <number or null>,
  "maxGasBid": <number>,
  "encodedBatch": "<hex string from encode_* tool>",
  "reasoning": "<brief explanation of your choice>"
}

Set offeredAPY for Yield intents (percentage, e.g. 4.2), offeredAmountOut for Swap intents (raw token units).
Set maxGasBid to 0.01 (FLOW) unless the intent's gasEscrow is higher.`;

// ─── Claude agentic loop for one intent ──────────────────────────────────────

interface BidRecommendation {
  strategy: string;
  offeredAPY: number | null;
  offeredAmountOut: number | null;
  estimatedFeeBPS: number | null;
  maxGasBid: number;
  encodedBatch: string;
  reasoning: string;
}

async function askClaudeForBestBid(intent: Intent): Promise<BidRecommendation | null> {
  console.log(`\n  [claude] Asking Claude for bid on intent #${intent.id}...`);

  const userMessage = `
Please analyze this FlowIntents intent and recommend the best bid strategy:

Intent #${intent.id}
- Type: ${intent.intentType}
- Principal: ${intent.principalAmount} FLOW
- Target APY: ${intent.targetAPY}% (for Yield intents)
- Min Amount Out: ${intent.minAmountOut ?? "N/A"} (for Swap intents)
- Max Fee: ${intent.maxFeeBPS != null ? intent.maxFeeBPS + " BPS" : "N/A"}
- Duration: ${intent.durationDays} days
- Principal Side: ${intent.principalSide}
- Gas Escrow Available: ${intent.gasEscrowBalance} FLOW
- Recipient EVM Address: ${intent.recipientEVMAddress ?? "use default COA address"}

For SWAP intents: use stgUSDC (${EVM_ADDRESSES.STG_USDC}) as the output token unless another is specified.
For YIELD intents: compare Ankr vs MORE Finance APY and pick the best one.

Use the available tools to research rates, then encode the strategy and return your bid JSON.
`.trim();

  const messages: Anthropic.MessageParam[] = [
    { role: "user", content: userMessage },
  ];

  // Agentic tool-use loop: Claude may call multiple tools before returning final answer
  let iterations = 0;
  const MAX_ITERATIONS = 10;

  while (iterations < MAX_ITERATIONS) {
    iterations++;

    const response = await claude.messages.create({
      model: BOT_CONFIG.CLAUDE_MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: CLAUDE_TOOLS,
      messages,
    });

    console.log(`  [claude] Response (iter ${iterations}): stop_reason=${response.stop_reason}`);

    // Process each content block
    for (const block of response.content) {
      if (block.type === "text") {
        const preview = block.text.slice(0, 200).replace(/\n/g, " ");
        console.log(`  [claude] Reasoning: ${preview}${block.text.length > 200 ? "..." : ""}`);
      } else if (block.type === "tool_use") {
        console.log(`  [claude] Tool call: ${block.name}(${JSON.stringify(block.input).slice(0, 100)})`);
      }
    }

    // If Claude finished with tool calls, execute them and feed results back
    if (response.stop_reason === "tool_use") {
      const assistantMessage: Anthropic.MessageParam = {
        role: "assistant",
        content: response.content,
      };
      messages.push(assistantMessage);

      const toolResults: Anthropic.ToolResultBlockParam[] = [];

      for (const block of response.content) {
        if (block.type === "tool_use") {
          console.log(`  [tools] Executing: ${block.name}`);
          try {
            const result = await executeTool(block.name, block.input as ToolInput);
            console.log(`  [tools] Result: ${result.slice(0, 150)}`);
            toolResults.push({
              type: "tool_result",
              tool_use_id: block.id,
              content: result,
            });
          } catch (err) {
            const errMsg = err instanceof Error ? err.message : String(err);
            console.error(`  [tools] Error in ${block.name}: ${errMsg}`);
            toolResults.push({
              type: "tool_result",
              tool_use_id: block.id,
              content: `Error: ${errMsg}`,
              is_error: true,
            });
          }
        }
      }

      messages.push({ role: "user", content: toolResults });
      continue;
    }

    // Claude is done — extract final text response
    if (response.stop_reason === "end_turn") {
      const textBlock = response.content.find((b) => b.type === "text");
      if (!textBlock || textBlock.type !== "text") {
        console.warn("  [claude] No text block in final response");
        return null;
      }

      // Extract JSON from Claude's response (may be wrapped in ```json ... ```)
      const text = textBlock.text;
      const jsonMatch = text.match(/```json\s*([\s\S]+?)\s*```/) ??
        text.match(/(\{[\s\S]+\})/);

      if (!jsonMatch) {
        console.warn("  [claude] Could not find JSON bid in response:", text.slice(0, 300));
        return null;
      }

      try {
        const bid = JSON.parse(jsonMatch[1]) as BidRecommendation;
        console.log(`  [claude] Bid recommendation: strategy=${bid.strategy}, reasoning="${bid.reasoning?.slice(0, 100)}"`);
        return bid;
      } catch (err) {
        console.error("  [claude] Failed to parse bid JSON:", err);
        console.error("  Raw JSON text:", jsonMatch[1].slice(0, 300));
        return null;
      }
    }

    // Unexpected stop reason
    console.warn(`  [claude] Unexpected stop_reason: ${response.stop_reason}`);
    return null;
  }

  console.warn(`  [claude] Exceeded max iterations (${MAX_ITERATIONS})`);
  return null;
}

// ─── Format intent for display ────────────────────────────────────────────────

function formatIntent(intent: Intent): string {
  const lines = [
    `Intent #${intent.id}`,
    `  Type:      ${intent.intentType}`,
    `  Principal: ${intent.principalAmount} FLOW`,
    intent.intentType === "Swap"
      ? `  Min Out:   ${intent.minAmountOut ?? "?"}  MaxFee: ${intent.maxFeeBPS ?? "?"}bps`
      : `  Target APY: ${intent.targetAPY}%`,
    `  Duration:  ${intent.durationDays}d  GasEscrow: ${intent.gasEscrowBalance} FLOW`,
    `  Owner:     ${intent.owner}`,
    `  Side:      ${intent.principalSide}`,
  ];
  return lines.join("\n");
}

// ─── Process a single intent ──────────────────────────────────────────────────

async function processIntent(intent: Intent): Promise<void> {
  console.log(`\n${"─".repeat(60)}`);
  console.log(formatIntent(intent));

  const bid = await askClaudeForBestBid(intent);

  if (!bid) {
    console.log(`  [bot] Claude returned no bid for intent #${intent.id} — skipping`);
    return;
  }

  if (!bid.encodedBatch) {
    console.log(`  [bot] Bid has no encodedBatch — skipping`);
    return;
  }

  const bidParams: BidParams = {
    intentID: intent.id,
    offeredAPY: bid.offeredAPY ?? undefined,
    offeredAmountOut: bid.offeredAmountOut ?? undefined,
    estimatedFeeBPS: bid.estimatedFeeBPS ?? undefined,
    maxGasBid: bid.maxGasBid ?? 0.01,
    strategy: bid.strategy,
    encodedBatch: bid.encodedBatch,
  };

  console.log(`\n  [bot] Submitting bid:`);
  console.log(`    strategy:        ${bid.strategy}`);
  if (bid.offeredAPY != null) console.log(`    offeredAPY:      ${bid.offeredAPY}%`);
  if (bid.offeredAmountOut != null) console.log(`    offeredAmountOut: ${bid.offeredAmountOut}`);
  console.log(`    maxGasBid:       ${bid.maxGasBid} FLOW`);
  console.log(`    reasoning:       ${bid.reasoning?.slice(0, 120)}`);

  const result = submitBid(bidParams);

  if (result.success) {
    markBidSubmitted(intent.id);
    console.log(`  [bot] Bid submitted successfully for intent #${intent.id}`);
  } else {
    console.error(`  [bot] Bid submission failed for intent #${intent.id}: ${result.output}`);
  }
}

// ─── Main solver loop ─────────────────────────────────────────────────────────

async function runSolverLoop(): Promise<never> {
  console.log(`\n${"═".repeat(60)}`);
  console.log(`  FlowIntents Solver Bot`);
  console.log(`  Model:      ${BOT_CONFIG.CLAUDE_MODEL}`);
  console.log(`  Network:    ${BOT_CONFIG.FLOW_NETWORK}`);
  console.log(`  DRY_RUN:    ${BOT_CONFIG.DRY_RUN}`);
  console.log(`  Poll every: ${BOT_CONFIG.POLL_INTERVAL_MS / 1000}s`);
  console.log(`${"═".repeat(60)}\n`);

  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      console.log(`[${new Date().toISOString()}] Polling for open intents...`);

      const openIntents = await getOpenIntents();
      console.log(`  Found ${openIntents.length} open intent(s)`);

      for (const intent of openIntents) {
        if (alreadyBidOnIntent(intent.id)) {
          console.log(`  Intent #${intent.id} — already bid, skipping`);
          continue;
        }
        await processIntent(intent);
      }
    } catch (err) {
      console.error(`[solver loop] Error:`, err);
    }

    console.log(`\n  Sleeping ${BOT_CONFIG.POLL_INTERVAL_MS / 1000}s until next poll...\n`);
    await sleep(BOT_CONFIG.POLL_INTERVAL_MS);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ─── Entry point ──────────────────────────────────────────────────────────────

runSolverLoop().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
