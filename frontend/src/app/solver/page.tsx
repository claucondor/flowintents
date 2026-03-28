"use client";

import React from "react";
import { motion } from "framer-motion";
import Link from "next/link";

const CONTRACTS = [
  { name: "IntentMarketplaceV0_3", address: "0xc65395858a38d8ff", note: "Intent creation + lifecycle" },
  { name: "BidManagerV0_3",        address: "0xc65395858a38d8ff", note: "Bid submission + winner selection" },
  { name: "IntentExecutorV0_3",    address: "0xc65395858a38d8ff", note: "Intent execution + gas escrow payout" },
  { name: "FlowIntentsComposerV4", address: "0x5cc14D3509639a819f4e8f796128Fcc1C9576D95", note: "EVM strategy executor" },
];

const EVENTS = [
  { name: "IntentMarketplaceV0_3.IntentCreated",   desc: "A new intent was posted. Fields: id, intentOwner, principalAmount, intentType, targetAPY, minAmountOut." },
  { name: "BidManagerV0_3.BidSubmitted",           desc: "A solver submitted a bid. Fields: bidID, intentID, solverAddress, offeredAPY, offeredAmountOut, maxGasBid, score." },
  { name: "BidManagerV0_3.WinnerSelected",         desc: "A winner was chosen. Fields: intentID, winningBidID, solverAddress. Winning solver should call executeIntent immediately." },
  { name: "IntentMarketplaceV0_3.IntentCompleted", desc: "Execution succeeded. Fields: id, owner, finalAmount." },
];

const STRATEGIES = [
  {
    id: "ankr-stake",
    label: "ankr-stake",
    title: "Ankr Liquid Staking",
    color: "#00C566",
    desc: "Stake FLOW into Ankr's liquid staking pool. Produces aFLOWEVMb cert tokens. Best for YIELD intents.",
    snippet: `// Encode an Ankr staking strategy
const batch = client.encodeANKRStakeStrategy(
  intent.principalAmount, // FLOW to stake
  myEvmAddress,           // receives aFLOWEVMb
)

await client.submitBid({
  intentID: intent.id,
  offeredAPY: intent.targetAPY + 1.5, // offer 1.5% above target
  strategy: 'ankr-stake',
  maxGasBid: 0.001,
  encodedBatch: batch,
})`,
  },
  {
    id: "punchswap-v2",
    label: "punchswap-v2",
    title: "PunchSwap UniV2 Swap",
    color: "#0047FF",
    desc: "Wrap FLOW → WFLOW → swap for stgUSDC via PunchSwap's UniV2 router. For SWAP intents.",
    snippet: `// Encode a PunchSwap strategy
const minOut = Math.floor((intent.minAmountOut ?? 0) * 1.02)
const batch = client.encodeWrapAndSwapStrategy(
  intent.principalAmount, // FLOW to wrap
  intent.principalAmount, // WFLOW to swap (all of it)
  TOKENS.stgUSDC,         // output token
  myEvmAddress,           // receives stgUSDC
  minOut,                 // min output (2% better than user's floor)
)

await client.submitBid({
  intentID: intent.id,
  offeredAmountOut: minOut,
  strategy: 'punchswap-v2',
  maxGasBid: 0.001,
  encodedBatch: batch,
})`,
  },
];

const sectionReveal = {
  initial: { opacity: 0, y: 16 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: "-60px" },
  transition: { duration: 0.4, ease: [0.22, 1, 0.36, 1] },
} as const;

export default function SolverDocsPage() {
  return (
    <div className="min-h-screen py-12 px-4 sm:px-8" style={{ background: "#050509" }}>
      <div className="max-w-4xl mx-auto">

        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-14"
        >
          <div
            className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Technical Documentation
          </div>
          <h1
            className="text-4xl font-bold text-[#F5F5F0] mb-4"
            style={{ letterSpacing: "-0.03em" }}
          >
            Build a Solver.
          </h1>
          <p className="text-[#9999A0] text-base leading-relaxed max-w-2xl">
            Solvers are autonomous agents that monitor open intents, submit competitive bids,
            and execute the winning strategy on-chain. Every successful execution earns the
            solver the full gas escrow deposited by the user.
          </p>
        </motion.div>

        {/* How solvers work */}
        <motion.section {...sectionReveal} className="mb-14">
          <div
            className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            How it works
          </div>
          <div className="border border-[#1a1a1a]" style={{ background: "#0D0D0D" }}>
            {[
              { step: "01", title: "Listen for intents", desc: "Poll getOpenIntents() or subscribe to IntentCreated events. Every new intent is an opportunity." },
              { step: "02", title: "Submit a bid", desc: "Call BidManagerV0_3.submitBid() with your offered terms (APY or amountOut) and an ABI-encoded strategy batch. Lower gas bids and better terms score higher." },
              { step: "03", title: "Watch for WinnerSelected", desc: "When the user (or the auto-selector) picks a winner, a WinnerSelected event fires. Check if your address won." },
              { step: "04", title: "Execute & collect", desc: "Call IntentExecutorV0_3.executeIntentV2(). The contract runs your encoded EVM strategy and pays you the full gas escrow." },
            ].map((item, i, arr) => (
              <div
                key={item.step}
                className={`p-6 flex gap-6 ${i < arr.length - 1 ? "border-b border-[#1a1a1a]" : ""}`}
              >
                <div
                  className="text-3xl font-bold text-[#1a1a1a] shrink-0 w-12 text-right"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  {item.step}
                </div>
                <div>
                  <div className="text-sm font-semibold text-[#F5F5F0] mb-1">{item.title}</div>
                  <p className="text-sm text-[#9999A0] leading-relaxed">{item.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </motion.section>

        {/* Quick start */}
        <motion.section {...sectionReveal} className="mb-14">
          <div
            className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Quick Start
          </div>
          <div className="border border-[#1a1a1a]" style={{ background: "#0D0D0D" }}>
            <div className="px-4 py-2 border-b border-[#1a1a1a] flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-red-500/50" />
              <span className="w-2.5 h-2.5 rounded-full bg-yellow-500/50" />
              <span className="w-2.5 h-2.5 rounded-full bg-[#00C566]/50" />
              <span
                className="ml-2 text-[10px] text-[#9999A0]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                terminal
              </span>
            </div>
            <pre
              className="p-5 text-[12px] leading-relaxed overflow-x-auto text-[#9999A0]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >{`# Clone and install
git clone https://github.com/your-repo/flowintents
cd flowintents/sdk && npm install

# Set your credentials
export SOLVER_PK="your_flow_private_key_hex"
export SOLVER_ADDRESS="0xYourFlowCadenceAddress"

# Run the example aggressive bot
npx ts-node solver-bot-a.ts

# Or run both bots competing in parallel
bash run-demo.sh`}
            </pre>
          </div>
          <p className="text-xs text-[#666660] mt-3" style={{ fontFamily: "'Space Mono', monospace" }}>
            See <code className="text-[#9999A0]">sdk/solver-bot-a.ts</code> and <code className="text-[#9999A0]">sdk/solver-bot-b.ts</code> for full working examples.
          </p>
        </motion.section>

        {/* Strategies */}
        <motion.section {...sectionReveal} className="mb-14">
          <div
            className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Built-in Strategies
          </div>
          <div className="space-y-6">
            {STRATEGIES.map((s) => (
              <div key={s.id} className="border border-[#1a1a1a]" style={{ background: "#0D0D0D" }}>
                {/* Strategy header */}
                <div className="px-6 py-4 border-b border-[#1a1a1a] flex items-center gap-3">
                  <span
                    className="px-2 py-0.5 text-[10px] font-bold border"
                    style={{
                      fontFamily: "'Space Mono', monospace",
                      color: s.color,
                      borderColor: `${s.color}40`,
                      background: `${s.color}10`,
                    }}
                  >
                    {s.label}
                  </span>
                  <span className="text-sm font-semibold text-[#F5F5F0]">{s.title}</span>
                </div>
                <div className="px-6 py-4 border-b border-[#1a1a1a]">
                  <p className="text-sm text-[#9999A0]">{s.desc}</p>
                </div>
                {/* Code */}
                <div className="px-4 py-2 border-b border-[#1a1a1a]">
                  <span
                    className="text-[10px] text-[#444440]"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    example
                  </span>
                </div>
                <pre
                  className="p-5 text-[11px] leading-relaxed overflow-x-auto"
                  style={{ fontFamily: "'Space Mono', monospace", color: "#9999A0" }}
                >
                  <code>{s.snippet}</code>
                </pre>
              </div>
            ))}
          </div>
        </motion.section>

        {/* Events */}
        <motion.section {...sectionReveal} className="mb-14">
          <div
            className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Events to listen to
          </div>
          <div className="border border-[#1a1a1a] overflow-hidden" style={{ background: "#0D0D0D" }}>
            {EVENTS.map((evt, i) => (
              <div key={evt.name} className={`p-5 ${i < EVENTS.length - 1 ? "border-b border-[#1a1a1a]" : ""}`}>
                <div
                  className="text-xs text-[#F5F5F0] font-bold mb-1.5"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  A.c65395858a38d8ff.{evt.name}
                </div>
                <p className="text-sm text-[#9999A0]">{evt.desc}</p>
              </div>
            ))}
          </div>
          <p className="text-xs text-[#444440] mt-3" style={{ fontFamily: "'Space Mono', monospace" }}>
            Poll via REST: GET /v1/events?type=A.c65395858a38d8ff.BidManagerV0_3.WinnerSelected&start_height=N&end_height=M
          </p>
        </motion.section>

        {/* Contracts */}
        <motion.section {...sectionReveal} className="mb-14">
          <div
            className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Contract Addresses — Flow Mainnet
          </div>
          <div className="border border-[#1a1a1a] overflow-hidden" style={{ background: "#0D0D0D" }}>
            {CONTRACTS.map((c, i) => (
              <div
                key={c.name}
                className={`px-6 py-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 ${i < CONTRACTS.length - 1 ? "border-b border-[#1a1a1a]" : ""}`}
              >
                <div>
                  <div
                    className="text-xs font-bold text-[#F5F5F0] mb-0.5"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    {c.name}
                  </div>
                  <div className="text-[11px] text-[#666660]">{c.note}</div>
                </div>
                <div
                  className="text-[11px] text-[#9999A0] font-mono"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  {c.address}
                </div>
              </div>
            ))}
          </div>
        </motion.section>

        {/* CTA */}
        <motion.section {...sectionReveal}>
          <div className="border border-[#0047FF]/20 p-8" style={{ background: "#0047FF08" }}>
            <div
              className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-4"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Ready to compete?
            </div>
            <h2 className="text-2xl font-bold text-[#F5F5F0] mb-3">
              Start building your solver today.
            </h2>
            <p className="text-[#9999A0] text-sm mb-6 max-w-lg">
              The FlowIntents SDK gives you everything you need: FCL signing, strategy encoders,
              and working bot examples. Fork it and make it better.
            </p>
            <div className="flex flex-wrap gap-3">
              <Link href="/live">
                <button
                  className="px-6 py-2.5 text-sm font-medium text-white"
                  style={{ background: "#0047FF", fontFamily: "'Space Grotesk', sans-serif" }}
                >
                  Watch Live Feed →
                </button>
              </Link>
              <Link href="/app">
                <button
                  className="px-6 py-2.5 text-sm font-medium text-[#F5F5F0] border border-[#1a1a1a] hover:border-[#0047FF]/40 transition-all"
                  style={{ fontFamily: "'Space Grotesk', sans-serif" }}
                >
                  Create Test Intent
                </button>
              </Link>
            </div>
          </div>
        </motion.section>

      </div>
    </div>
  );
}
