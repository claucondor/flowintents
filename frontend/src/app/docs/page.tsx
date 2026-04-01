"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Link from "next/link";

// ── Section definitions ───────────────────────────────────────────────────────

const SECTIONS = [
  { id: "overview",        label: "Overview" },
  { id: "architecture",    label: "Architecture" },
  { id: "intent-types",    label: "Intent Types" },
  { id: "contracts",       label: "Deployed Contracts" },
  { id: "solver-guide",    label: "Solver Guide" },
  { id: "sdk-reference",   label: "SDK Reference" },
  { id: "strategy-catalog", label: "Strategy Catalog" },
  { id: "submit-intent",   label: "Submit an Intent" },
] as const;

type SectionId = typeof SECTIONS[number]["id"];

// ── Contract addresses ────────────────────────────────────────────────────────

const CADENCE_ACCOUNT = "0xc65395858a38d8ff";
const COMPOSER_V5     = "0x34BfEcBB547875a3bBA86521a56B06f8197f2913";

const CONTRACTS = [
  {
    name: "IntentMarketplaceV0_4",
    address: CADENCE_ACCOUNT,
    chain: "Cadence",
    version: "V0_4",
    desc: "Intent creation + lifecycle. Stores open intents; commission escrow held in FLOW vault.",
    explorer: `https://www.flowscan.io/account/${CADENCE_ACCOUNT}`,
  },
  {
    name: "BidManagerV0_4",
    address: CADENCE_ACCOUNT,
    chain: "Cadence",
    version: "V0_4",
    desc: "Bid submission + winner selection. Scores bids: yield×0.7 + gas_efficiency×0.3.",
    explorer: `https://www.flowscan.io/account/${CADENCE_ACCOUNT}`,
  },
  {
    name: "IntentExecutorV0_4",
    address: CADENCE_ACCOUNT,
    chain: "Cadence",
    version: "V0_4",
    desc: "User-executed model — user signs and executes winning strategy via their own COA.",
    explorer: `https://www.flowscan.io/account/${CADENCE_ACCOUNT}`,
  },
  {
    name: "SolverRegistryV0_1",
    address: CADENCE_ACCOUNT,
    chain: "Cadence",
    version: "V0_1",
    desc: "Registers and verifies solver agents via ERC-8004 identity NFT on Flow EVM.",
    explorer: `https://www.flowscan.io/account/${CADENCE_ACCOUNT}`,
  },
  {
    name: "FlowIntentsComposerV5",
    address: COMPOSER_V5,
    chain: "Flow EVM",
    version: "V5",
    desc: "Permissionless EVM strategy executor. Any COA can call. Delta-sweep output tokens to recipient. chainId 747.",
    explorer: `https://evm.flowscan.io/address/${COMPOSER_V5}`,
  },
] as const;

// ── Strategy catalog ──────────────────────────────────────────────────────────

const STRATEGIES = [
  {
    id: "ankr-stake",
    label: "ankr-stake",
    title: "Ankr Liquid Staking",
    bot: "Bot A",
    type: "Yield",
    apy: "~4.2% APY",
    color: "#00C566",
    desc: "Stake FLOW into Ankr's liquid staking pool on Flow EVM. Produces aFLOWEVMb certificate tokens. Shares stay in user's COA.",
    snippet: `import { encodeANKRStakeStrategy, submitBid } from '@flowintents/solver-sdk'

// Encode the Ankr staking batch
const batch = encodeANKRStakeStrategy(
  intent.principalAmount,
  COMPOSER_V5   // "0x34BfEcBB547875a3bBA86521a56B06f8197f2913"
)

await submitBid({
  intentID:    intent.id,
  offeredAPY:  4.2,
  strategy:    'ankr-stake',
  maxGasBid:   0.001,
  encodedBatch: batch,
})`,
  },
  {
    id: "alphayield-wflow-vault",
    label: "alphayield-wflow-vault",
    title: "AlphaYield WFLOW Vault",
    bot: "Bot B",
    type: "Yield",
    apy: "~19.9% APY",
    color: "#F5C542",
    desc: "Deposit WFLOW into AlphaYield's ERC-4626 vault — an ankrFLOW looping strategy built on MORE Markets. User receives syWFLOWv shares.",
    snippet: `import { encodeAlphaYieldStrategy, submitBid } from '@flowintents/solver-sdk'

// Encode: wrap FLOW → WFLOW → approve → deposit into vault
const batch = encodeAlphaYieldStrategy(
  intent.principalAmount,
  COMPOSER_V5
)

await submitBid({
  intentID:    intent.id,
  offeredAPY:  19.9,
  strategy:    'alphayield-wflow-vault',
  maxGasBid:   0.002,
  encodedBatch: batch,
})`,
  },
  {
    id: "punchswap-direct",
    label: "wrap-and-swap-punchswap",
    title: "PunchSwap Direct Swap",
    bot: "Bot A",
    type: "Swap",
    apy: "Best price",
    color: "#0047FF",
    desc: "Wrap FLOW → WFLOW, then swap for stgUSDC via PunchSwap V2 router. Direct route — best price for stgUSDC.",
    snippet: `import {
  getPunchSwapQuote,
  encodeWrapAndSwapStrategy,
  submitBid,
  TOKENS,
} from '@flowintents/solver-sdk'

const amount = BigInt(Math.floor(intent.principalAmount * 1e18))
const quote  = await getPunchSwapQuote(amount, TOKENS.stgUSDC)

const batch = encodeWrapAndSwapStrategy(
  amount,
  amount,
  TOKENS.stgUSDC,
  COMPOSER_V5,  // output swept to Composer for delta-sweep
  BigInt(Math.floor(Number(quote) * 0.95)),  // 5% slippage
)

await submitBid({
  intentID:        intent.id,
  offeredAmountOut: Number(quote) / 1e6,
  strategy:        'wrap-and-swap-punchswap',
  maxGasBid:       0.001,
  encodedBatch:    batch,
})`,
  },
  {
    id: "multihop-swap",
    label: "multihop-wflow-usdf-stgusdc",
    title: "PunchSwap Multi-Hop Swap",
    bot: "Bot B",
    type: "Swap",
    apy: "Alternative route",
    color: "#5B8EFF",
    desc: "Multi-hop route: WFLOW → USDF (PYUSD) → stgUSDC via PunchSwap. Alternative path through USDF liquidity.",
    snippet: `import {
  getPunchSwapMultiHopQuote,
  encodeMultiHopSwapStrategy,
  submitBid,
  TOKENS,
} from '@flowintents/solver-sdk'

const amount = BigInt(Math.floor(intent.principalAmount * 1e18))
const quote  = await getPunchSwapMultiHopQuote(
  amount, TOKENS.USDF, TOKENS.stgUSDC
)

const batch = encodeMultiHopSwapStrategy(
  amount,
  TOKENS.USDF,
  TOKENS.stgUSDC,
  COMPOSER_V5,
  BigInt(Math.floor(Number(quote) * 0.95)),
)

await submitBid({
  intentID:        intent.id,
  offeredAmountOut: Number(quote) / 1e6,
  strategy:        'multihop-wflow-usdf-stgusdc',
  maxGasBid:       0.002,
  encodedBatch:    batch,
})`,
  },
] as const;

// ── Events ────────────────────────────────────────────────────────────────────

const EVENTS = [
  {
    name: "IntentMarketplaceV0_4.IntentCreated",
    fields: "id, owner, intentType, principalAmount, tokenOut, deliverySide, durationDays",
    desc: "A new intent was posted. Poll this to find open intents.",
  },
  {
    name: "BidManagerV0_4.BidSubmitted",
    fields: "bidID, intentID, solverAddress, offeredAPY, offeredAmountOut, maxGasBid, score",
    desc: "A solver submitted a bid. Track competition and scoring.",
  },
  {
    name: "BidManagerV0_4.WinnerSelected",
    fields: "intentID, winningBidID, solverAddress",
    desc: "User selected the winning bid. User will now execute the strategy.",
  },
  {
    name: "IntentMarketplaceV0_4.IntentCompleted",
    fields: "id, owner",
    desc: "User executed the strategy. Commission escrow released to solver.",
  },
] as const;

// ── Sub-components ────────────────────────────────────────────────────────────

function SectionLabel({ children, color = "#0047FF" }: { children: React.ReactNode; color?: string }) {
  return (
    <div
      className="text-[10px] uppercase tracking-widest mb-5"
      style={{ fontFamily: "'Space Mono', monospace", color }}
    >
      {children}
    </div>
  );
}

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2
      className="text-2xl font-bold text-[var(--text-primary)] mb-4"
      style={{ letterSpacing: "-0.025em" }}
    >
      {children}
    </h2>
  );
}

function CodeBlock({
  lang,
  children,
  title,
}: {
  lang: string;
  children: string;
  title?: string;
}) {
  return (
    <div className="border border-[var(--border)] overflow-hidden" style={{ background: "var(--bg-card)" }}>
      <div className="px-4 py-2 border-b border-[var(--border)] flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="w-2.5 h-2.5 rounded-full bg-red-500/40" />
          <span className="w-2.5 h-2.5 rounded-full bg-yellow-500/40" />
          <span className="w-2.5 h-2.5 rounded-full bg-[#00C566]/40" />
          {title && (
            <span
              className="ml-2 text-[10px] text-[var(--text-muted)]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {title}
            </span>
          )}
        </div>
        <span
          className="text-[10px] px-2 py-0.5 border border-[#00C566]/20 text-[#00C566]/60"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          {lang}
        </span>
      </div>
      <pre
        className="p-5 text-[11.5px] leading-relaxed overflow-x-auto text-[var(--text-secondary)]"
        style={{ fontFamily: "'Space Mono', monospace" }}
      >
        <code>{children}</code>
      </pre>
    </div>
  );
}

function Badge({ children, color = "#00C566" }: { children: React.ReactNode; color?: string }) {
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 text-[10px] font-bold border"
      style={{
        fontFamily: "'Space Mono', monospace",
        color,
        borderColor: `${color}40`,
        background: `${color}12`,
      }}
    >
      {children}
    </span>
  );
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

function Sidebar({
  activeSection,
  onSelect,
}: {
  activeSection: SectionId;
  onSelect: (id: SectionId) => void;
}) {
  return (
    <aside className="hidden lg:block w-52 shrink-0">
      <div className="sticky top-24">
        <div
          className="text-[9px] text-[var(--text-muted)] uppercase tracking-widest mb-4"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          On this page
        </div>
        <nav className="space-y-0.5">
          {SECTIONS.map((s) => {
            const isActive = activeSection === s.id;
            return (
              <button
                key={s.id}
                onClick={() => onSelect(s.id as SectionId)}
                className="w-full text-left block py-1.5 px-3 text-xs transition-all border-l-2"
                style={{
                  fontFamily: "'Space Grotesk', sans-serif",
                  color: isActive ? "var(--text-primary)" : "var(--text-muted)",
                  borderColor: isActive ? "#00C566" : "transparent",
                }}
              >
                {s.label}
              </button>
            );
          })}
        </nav>
        <div className="mt-8 border-t border-[var(--border)] pt-6 space-y-2">
          <Link
            href="/live"
            className="block text-xs text-[var(--text-muted)] hover:text-[#00C566] transition-colors py-1"
            style={{ fontFamily: "'Space Grotesk', sans-serif" }}
          >
            Live Feed →
          </Link>
          <Link
            href="/solver"
            className="block text-xs text-[var(--text-muted)] hover:text-[#0047FF] transition-colors py-1"
            style={{ fontFamily: "'Space Grotesk', sans-serif" }}
          >
            Solver Guide →
          </Link>
          <Link
            href="/app"
            className="block text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors py-1"
            style={{ fontFamily: "'Space Grotesk', sans-serif" }}
          >
            Create Intent →
          </Link>
        </div>
      </div>
    </aside>
  );
}

// ── Mobile nav (pills) ────────────────────────────────────────────────────────

function MobileNav({
  activeSection,
  onSelect,
}: {
  activeSection: SectionId;
  onSelect: (id: SectionId) => void;
}) {
  return (
    <div className="lg:hidden mb-6 overflow-x-auto">
      <div className="flex gap-2 pb-2 min-w-max">
        {SECTIONS.map((s) => {
          const isActive = activeSection === s.id;
          return (
            <button
              key={s.id}
              onClick={() => onSelect(s.id as SectionId)}
              className="shrink-0 px-3 py-1.5 text-xs border transition-all"
              style={{
                fontFamily: "'Space Grotesk', sans-serif",
                color: isActive ? "var(--accent)" : "var(--text-muted)",
                borderColor: isActive ? "var(--accent)" : "var(--border)",
                background: isActive ? "#00C56612" : "transparent",
              }}
            >
              {s.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ── Section content components ────────────────────────────────────────────────

function SectionOverview() {
  return (
    <>
      <SectionLabel>01 — Overview</SectionLabel>
      <SectionHeading>What is FlowIntents?</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        FlowIntents is an intent-based DeFi protocol on Flow blockchain. Instead of manually
        executing transactions, users declare what they want — "earn yield on 100 FLOW" or
        "swap 50 FLOW to stgUSDC" — and registered AI solver agents compete to fulfill those
        goals at the best possible terms.
      </p>

      <div className="border border-[var(--border)]" style={{ background: "var(--bg-card)" }}>
        {[
          {
            step: "01",
            title: "Submit an intent",
            desc: "User declares a financial goal (yield or swap), specifying principal amount and duration. Only commission escrow is deposited upfront — the principal stays in the user's wallet.",
            color: "#0047FF",
          },
          {
            step: "02",
            title: "Solvers scan and bid",
            desc: "Registered AI solver agents read open intents via the SDK and submit bids with their offered APY or output amount, along with an ABI-encoded strategy batch.",
            color: "#F5C542",
          },
          {
            step: "03",
            title: "User selects winner",
            desc: "The intent owner reviews bids (scored by BidManagerV0_4) and selects the best. Score = (offered terms × reputation × 0.7) + (gas efficiency × 0.3).",
            color: "#F5C542",
          },
          {
            step: "04",
            title: "Execute and settle",
            desc: "The user signs and runs the winning strategy via their own COA. FlowIntentsComposerV5.sol executes the DeFi steps on Flow EVM. Commission escrow is paid to the solver automatically.",
            color: "#00C566",
          },
        ].map((item, i, arr) => (
          <div
            key={item.step}
            className={`p-6 flex gap-5 ${i < arr.length - 1 ? "border-b border-[var(--border)]" : ""}`}
          >
            <div
              className="text-2xl font-bold shrink-0 w-10 text-right tabular-nums"
              style={{ fontFamily: "'Space Mono', monospace", color: "var(--border)" }}
            >
              {item.step}
            </div>
            <div>
              <div
                className="text-sm font-semibold mb-1.5"
                style={{ color: item.color }}
              >
                {item.title}
              </div>
              <p className="text-sm text-[var(--text-secondary)] leading-relaxed">{item.desc}</p>
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

function SectionArchitecture() {
  return (
    <>
      <SectionLabel>02 — Architecture</SectionLabel>
      <SectionHeading>How the layers connect</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        FlowIntents spans two execution environments bridged by Flow's native COA
        (Cadence-Owned Account) mechanism: Cadence for intent lifecycle and settlement,
        Flow EVM for DeFi protocol execution.
      </p>

      {/* Architecture diagram */}
      <div className="border border-[var(--border)] p-6" style={{ background: "var(--bg-card)" }}>
        <div className="grid grid-cols-3 gap-4 text-center text-[11px]" style={{ fontFamily: "'Space Mono', monospace" }}>
          {/* Row 1 */}
          <div className="col-span-3 flex justify-center">
            <div className="px-5 py-3 border border-[#0047FF]/40 text-[#0047FF]" style={{ background: "#0047FF10" }}>
              User
            </div>
          </div>

          {/* Arrow down */}
          <div className="col-span-3 flex justify-center items-center text-[var(--text-muted)] py-1 text-base">↓ submitIntent + commission escrow</div>

          {/* Cadence layer */}
          <div className="col-span-3 border border-[var(--border)] p-4" style={{ background: "var(--bg-elevated)" }}>
            <div className="text-[9px] text-[var(--text-muted)] uppercase tracking-widest mb-3">Cadence Layer — {CADENCE_ACCOUNT}</div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {[
                "IntentMarketplaceV0_4",
                "BidManagerV0_4",
                "IntentExecutorV0_4",
                "SolverRegistryV0_1",
              ].map((c) => (
                <div key={c} className="px-2 py-2 border border-[var(--border)] text-[var(--text-secondary)] text-[10px]">
                  {c}
                </div>
              ))}
            </div>
          </div>

          {/* COA bridge */}
          <div className="col-span-3 flex justify-center items-center text-[var(--text-muted)] py-1 text-base">↓ COA cross-VM call</div>

          {/* EVM layer */}
          <div className="col-span-3 border border-[#00C566]/20 p-4" style={{ background: "#00C56608" }}>
            <div className="text-[9px] text-[#00C566]/50 uppercase tracking-widest mb-3">Flow EVM — chainId 747</div>
            <div className="flex justify-center">
              <div className="px-4 py-2 border border-[#00C566]/30 text-[#00C566] text-[10px]" style={{ background: "#00C56614" }}>
                FlowIntentsComposerV5.sol<br />
                <span className="text-[9px] text-[#00C566]/50">{COMPOSER_V5}</span>
              </div>
            </div>
          </div>

          {/* Protocols */}
          <div className="col-span-3 flex justify-center items-center text-[var(--text-muted)] py-1 text-base">↓ execute strategy</div>

          <div className="col-span-3 border border-[var(--border)] p-4" style={{ background: "var(--bg-elevated)" }}>
            <div className="text-[9px] text-[var(--text-muted)] uppercase tracking-widest mb-3">DeFi Protocols on Flow EVM</div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {[
                { name: "Ankr", desc: "Liquid staking ~4.2%" },
                { name: "AlphaYield", desc: "ERC-4626 vault ~19.9%" },
                { name: "PunchSwap", desc: "UniswapV2 DEX" },
                { name: "WFLOW", desc: "Wrapped FLOW ERC-20" },
              ].map((p) => (
                <div key={p.name} className="px-2 py-2 border border-[var(--border)] text-[10px]">
                  <div className="text-[var(--text-secondary)]">{p.name}</div>
                  <div className="text-[var(--text-muted)] text-[9px]">{p.desc}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Component table */}
      <div className="mt-6 border border-[var(--border)] overflow-hidden" style={{ background: "var(--bg-card)" }}>
        <div className="grid grid-cols-3 px-5 py-2.5 border-b border-[var(--border)] text-[10px] text-[var(--text-muted)] uppercase tracking-widest" style={{ fontFamily: "'Space Mono', monospace" }}>
          <span>Layer</span>
          <span>Component</span>
          <span>Role</span>
        </div>
        {[
          { layer: "Cadence", name: "IntentMarketplaceV0_4", role: "Stores open intents; escrow held in FLOW vault" },
          { layer: "Cadence", name: "BidManagerV0_4", role: "Receives bids, scores them, selects winner" },
          { layer: "Cadence", name: "SolverRegistryV0_1", role: "Registers / verifies solver agents via ERC-8004" },
          { layer: "Cadence", name: "IntentExecutorV0_4", role: "User executes winning bid via COA cross-VM call" },
          { layer: "EVM", name: "FlowIntentsComposerV5", role: "Permissionless multi-step DeFi strategy executor" },
        ].map((row, i, arr) => (
          <div
            key={row.name}
            className={`grid grid-cols-3 px-5 py-3 text-xs ${i < arr.length - 1 ? "border-b border-[var(--border)]" : ""}`}
          >
            <span
              className="text-[var(--text-muted)]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {row.layer}
            </span>
            <span
              className="text-[var(--text-primary)] text-[11px]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {row.name}
            </span>
            <span className="text-[var(--text-muted)]">{row.role}</span>
          </div>
        ))}
      </div>
    </>
  );
}

function SectionIntentTypes() {
  return (
    <>
      <SectionLabel>03 — Intent Types</SectionLabel>
      <SectionHeading>Yield vs Swap</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        FlowIntents V0_4 supports two intent types. Both use the same bid infrastructure;
        only the scoring formula and required fields differ.
      </p>

      <div className="grid sm:grid-cols-2 gap-4 mb-8">
        {[
          {
            type: "Yield",
            typeNum: "0",
            color: "#00C566",
            desc: "User wants to maximize APY on their FLOW. Solver offers a percentage return and encodes a staking or vault deposit strategy.",
            fields: [
              { name: "principalAmount", type: "UFix64", note: "FLOW to put to work" },
              { name: "targetAPY", type: "UFix64", note: "Minimum acceptable APY %" },
              { name: "durationDays", type: "UInt64", note: "Commitment period" },
              { name: "deliverySide", type: "UInt8", note: "0=Cadence, 1=EVM" },
              { name: "commissionEscrow", type: "UFix64", note: "Solver incentive (FLOW)" },
            ],
            scoring: "offeredAPY × 0.7 + gasEfficiency × 0.3",
          },
          {
            type: "Swap",
            typeNum: "1",
            color: "#0047FF",
            desc: "User wants to exchange FLOW for another token at the best rate. Solver offers the output amount and encodes a DEX swap strategy.",
            fields: [
              { name: "principalAmount", type: "UFix64", note: "FLOW input amount" },
              { name: "tokenOut", type: "String", note: "EVM address of output token" },
              { name: "minAmountOut", type: "UFix64", note: "Minimum output required" },
              { name: "durationDays", type: "UInt64", note: "Intent expiry window" },
              { name: "commissionEscrow", type: "UFix64", note: "Solver incentive (FLOW)" },
            ],
            scoring: "offeredAmountOut × rep × 0.7 + gasEfficiency × 0.3",
          },
        ].map((intent) => (
          <div key={intent.type} className="border border-[var(--border)]" style={{ background: "var(--bg-card)" }}>
            <div className="px-5 py-4 border-b border-[var(--border)] flex items-center gap-3">
              <Badge color={intent.color}>{intent.type}</Badge>
              <span
                className="text-[10px] text-[var(--text-muted)]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                intentType: {intent.typeNum}
              </span>
            </div>
            <div className="px-5 py-4 border-b border-[var(--border)]">
              <p className="text-sm text-[var(--text-secondary)] leading-relaxed">{intent.desc}</p>
            </div>
            <div className="px-5 py-4 border-b border-[var(--border)]">
              <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest mb-3" style={{ fontFamily: "'Space Mono', monospace" }}>
                Required fields
              </div>
              <div className="space-y-1.5">
                {intent.fields.map((f) => (
                  <div key={f.name} className="flex items-start gap-3 text-xs">
                    <span className="text-[var(--text-primary)] w-36 shrink-0" style={{ fontFamily: "'Space Mono', monospace" }}>{f.name}</span>
                    <span className="text-[var(--text-muted)] w-16 shrink-0" style={{ fontFamily: "'Space Mono', monospace" }}>{f.type}</span>
                    <span className="text-[var(--text-muted)]">{f.note}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="px-5 py-3">
              <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest mb-1.5" style={{ fontFamily: "'Space Mono', monospace" }}>
                Scoring formula
              </div>
              <code
                className="text-[11px] text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                score = {intent.scoring}
              </code>
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

function SectionContracts() {
  return (
    <>
      <SectionLabel>04 — Deployed Contracts</SectionLabel>
      <SectionHeading>Flow Mainnet Addresses</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-6 max-w-2xl">
        All Cadence contracts are deployed on the same account. The EVM composer runs on
        Flow EVM (chainId 747) — same network, separate execution environment.
      </p>

      <div className="border border-[var(--border)] overflow-hidden" style={{ background: "var(--bg-card)" }}>
        <div
          className="grid grid-cols-12 px-5 py-2.5 border-b border-[var(--border)] text-[9px] text-[var(--text-muted)] uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          <span className="col-span-4">Contract</span>
          <span className="col-span-2">Chain</span>
          <span className="col-span-1 text-center">Ver</span>
          <span className="col-span-5">Address</span>
        </div>
        {CONTRACTS.map((c, i) => (
          <div
            key={c.name}
            className={`grid grid-cols-12 px-5 py-4 items-start gap-x-2 ${i < CONTRACTS.length - 1 ? "border-b border-[var(--border)]" : ""}`}
          >
            <div className="col-span-4">
              <div
                className="text-xs font-bold text-[var(--text-primary)] mb-0.5"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {c.name}
              </div>
              <div className="text-[11px] text-[var(--text-muted)] leading-snug pr-4">{c.desc}</div>
            </div>
            <div className="col-span-2">
              <Badge color={c.chain === "Cadence" ? "var(--text-secondary)" : "var(--accent)"}>
                {c.chain}
              </Badge>
            </div>
            <div className="col-span-1 text-center">
              <Badge color="#F5C542">{c.version}</Badge>
            </div>
            <div className="col-span-5">
              <a
                href={c.explorer}
                target="_blank"
                rel="noopener noreferrer"
                className="text-[11px] text-[var(--text-secondary)] hover:text-[#00C566] transition-colors break-all"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {c.address} ↗
              </a>
            </div>
          </div>
        ))}
      </div>

      {/* EVM Tokens */}
      <div className="mt-6 border border-[var(--border)] overflow-hidden" style={{ background: "var(--bg-card)" }}>
        <div className="px-5 py-3 border-b border-[var(--border)]">
          <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest" style={{ fontFamily: "'Space Mono', monospace" }}>
            Key EVM Token Addresses (Flow EVM · chainId 747)
          </div>
        </div>
        {[
          { name: "WFLOW", address: "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e", note: "Wrapped FLOW ERC-20" },
          { name: "stgUSDC", address: "0x1b97b49f28754e8c451bbf4d8bb4a32c9a31d7c1", note: "Stargate USDC — main swap target" },
          { name: "USDF (PYUSD)", address: "0x4A96a408F5EB872b94a4b27b97b08eA77bc55784", note: "PYUSD — multi-hop route" },
          { name: "PunchSwap Router", address: "0xA671B20dE3a479b2D895A9A4f8B1cC4AF24Da52c", note: "UniswapV2-compatible DEX" },
        ].map((t, i, arr) => (
          <div key={t.name} className={`px-5 py-3 flex items-center gap-4 text-xs ${i < arr.length - 1 ? "border-b border-[var(--border)]" : ""}`}>
            <span className="w-28 text-[var(--text-primary)] shrink-0" style={{ fontFamily: "'Space Mono', monospace" }}>{t.name}</span>
            <span className="text-[var(--text-secondary)] flex-1" style={{ fontFamily: "'Space Mono', monospace" }}>{t.address}</span>
            <span className="text-[var(--text-muted)] text-[11px]">{t.note}</span>
          </div>
        ))}
      </div>
    </>
  );
}

function SectionSolverGuide() {
  return (
    <>
      <SectionLabel>05 — Solver Guide</SectionLabel>
      <SectionHeading>Build an autonomous solver</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        Solvers are autonomous agents that monitor open intents, evaluate which strategy
        offers the best terms, submit competitive bids, and earn the commission escrow for
        each successful execution. Here is the step-by-step lifecycle.
      </p>

      {/* Steps */}
      <div className="border border-[var(--border)] mb-8" style={{ background: "var(--bg-card)" }}>
        {[
          {
            step: "01",
            title: "Register your solver",
            desc: "Call registerSolver.cdc to add your Cadence address to SolverRegistryV0_1. The registry verifies your ERC-8004 agent NFT on Flow EVM — required before you can bid.",
            color: "#0047FF",
          },
          {
            step: "02",
            title: "Listen for open intents",
            desc: "Poll IntentMarketplaceV0_4 using the SDK's EventListener or fetch open intents via a Cadence script. Subscribe to the IntentCreated event for real-time updates.",
            color: "var(--text-secondary)",
          },
          {
            step: "03",
            title: "Evaluate and encode a strategy",
            desc: "For each new intent, use StrategyEngine.evaluate() to get ranked strategies with expected APY. Then encode the selected strategy into an ABI-encoded StrategyStep[] batch for FlowIntentsComposerV5.",
            color: "#F5C542",
          },
          {
            step: "04",
            title: "Submit a bid",
            desc: "Call BidManagerV0_4.submitBid() via submitBidV0_4.cdc with your offered terms and encodedBatch. Compete on APY (yield) or amountOut (swap), and keep maxGasBid low.",
            color: "#F5C542",
          },
          {
            step: "05",
            title: "User selects winner — you get paid",
            desc: "The intent owner picks the highest-scored bid. When the user executes the intent, your strategy runs on-chain via their COA. The commission escrow is transferred to your address automatically.",
            color: "#00C566",
          },
        ].map((item, i, arr) => (
          <div
            key={item.step}
            className={`p-6 flex gap-5 ${i < arr.length - 1 ? "border-b border-[var(--border)]" : ""}`}
          >
            <div
              className="text-2xl font-bold shrink-0 w-10 text-right tabular-nums"
              style={{ fontFamily: "'Space Mono', monospace", color: "var(--border)" }}
            >
              {item.step}
            </div>
            <div>
              <div className="text-sm font-semibold mb-1.5" style={{ color: item.color }}>
                {item.title}
              </div>
              <p className="text-sm text-[var(--text-secondary)] leading-relaxed">{item.desc}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Quickstart shell */}
      <CodeBlock lang="bash" title="terminal">
{`# Clone and install the SDK
git clone https://github.com/your-repo/flowintents
cd flowintents/sdk && npm install

# Set environment variables
export SOLVER_FLOW_ADDRESS="0xYourCadenceAddress"
export SOLVER_FLOW_PK="yourHexPrivateKeyNoPrefix"
export SOLVER_EVM_ADDRESS="0xYourEVMAddress"
export SOLVER_EVM_PK="yourEVMHexPrivateKey"

# Run the reference solver bots
npx ts-node solver-bot/src/index.ts      # LLM-powered bot (needs ANTHROPIC_API_KEY)
# or manually:
npx ts-node sdk/solver-bot-a.ts          # Aggressive yield + direct swap
npx ts-node sdk/solver-bot-b.ts          # AlphaYield + multi-hop swap`}
      </CodeBlock>

      {/* Scoring formula */}
      <div className="mt-6 border border-[var(--border)] p-5" style={{ background: "var(--bg-card)" }}>
        <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest mb-4" style={{ fontFamily: "'Space Mono', monospace" }}>
          Bid scoring — BidManagerV0_4
        </div>
        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <div className="text-[11px] text-[var(--text-muted)] mb-1.5" style={{ fontFamily: "'Space Mono', monospace" }}>Yield intents</div>
            <code className="text-sm text-[#00C566]" style={{ fontFamily: "'Space Mono', monospace" }}>
              score = offeredAPY × 0.7 + gasEff × 0.3
            </code>
          </div>
          <div>
            <div className="text-[11px] text-[var(--text-muted)] mb-1.5" style={{ fontFamily: "'Space Mono', monospace" }}>Swap intents</div>
            <code className="text-sm text-[#00C566]" style={{ fontFamily: "'Space Mono', monospace" }}>
              score = amountOut × rep × 0.7 + gasEff × 0.3
            </code>
          </div>
        </div>
        <p className="text-xs text-[var(--text-muted)] mt-4">
          gasEff = (maxGasBid) &mdash; lower bids score higher on the gas dimension. Ties are broken by lowest gas bid.
        </p>
      </div>

      {/* Events to subscribe */}
      <div className="mt-6 border border-[var(--border)] overflow-hidden" style={{ background: "var(--bg-card)" }}>
        <div className="px-5 py-3 border-b border-[var(--border)]">
          <div className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest" style={{ fontFamily: "'Space Mono', monospace" }}>
            Events to subscribe to
          </div>
        </div>
        {EVENTS.map((evt, i) => (
          <div key={evt.name} className={`px-5 py-4 ${i < EVENTS.length - 1 ? "border-b border-[var(--border)]" : ""}`}>
            <div className="text-xs font-bold text-[var(--text-primary)] mb-1" style={{ fontFamily: "'Space Mono', monospace" }}>
              A.{CADENCE_ACCOUNT.slice(2)}.{evt.name}
            </div>
            <div className="text-[11px] text-[var(--text-muted)] mb-1" style={{ fontFamily: "'Space Mono', monospace" }}>
              {evt.fields}
            </div>
            <p className="text-xs text-[var(--text-muted)]">{evt.desc}</p>
          </div>
        ))}
        <div className="px-5 py-3 border-t border-[var(--border)]">
          <code className="text-[10px] text-[var(--text-muted)]" style={{ fontFamily: "'Space Mono', monospace" }}>
            GET /v1/events?type=A.c65395858a38d8ff.BidManagerV0_4.BidSubmitted&start_height=N&end_height=M
          </code>
        </div>
      </div>
    </>
  );
}

function SectionSDKReference() {
  return (
    <>
      <SectionLabel>06 — SDK Reference</SectionLabel>
      <SectionHeading>@flowintents/solver-sdk</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        The SDK provides everything a solver needs: event listening, strategy evaluation,
        bid construction, and FCL transaction submission.
      </p>

      {/* Install */}
      <CodeBlock lang="bash" title="install">
{`cd flowintents/sdk
npm install
# The SDK is local — import from the dist build
import { ... } from '../sdk/dist/src/index'`}
      </CodeBlock>

      <div className="mt-6 space-y-4">

        {/* SolverConfig */}
        <CodeBlock lang="typescript" title="SolverConfig">
{`import type { SolverConfig } from '@flowintents/solver-sdk'

const config: SolverConfig = {
  flowPrivateKey: process.env.SOLVER_FLOW_PK!,   // hex, no 0x
  flowAddress:    process.env.SOLVER_FLOW_ADDRESS!,  // 0x-prefixed
  evmPrivateKey:  process.env.SOLVER_EVM_PK!,
  evmAddress:     process.env.SOLVER_EVM_ADDRESS!,
  agentTokenId:   1,        // ERC-8004 token ID after registration
  minAPYThreshold: 3.5,     // minimum APY to bother bidding
  maxPrincipal:   "10000.00000000",
  openRouterApiKey: process.env.OPENROUTER_KEY,  // optional AI routing
}`}
        </CodeBlock>

        {/* EventListener */}
        <CodeBlock lang="typescript" title="EventListener — subscribe to intents">
{`import { EventListener } from '@flowintents/solver-sdk'

const listener = new EventListener(
  'c65395858a38d8ff',                  // contract account (no 0x)
  'https://rest-mainnet.onflow.org'
)

listener
  .onIntent(async (intent) => {
    console.log('New intent:', intent.id, intent.status)
    // intent: { id, owner, tokenType, principalAmount,
    //           targetAPY, durationDays, expiryBlock, status }
  })
  .onError((err) => console.error('Listener error:', err))
  .start()

// Stop when done
// listener.stop()`}
        </CodeBlock>

        {/* StrategyEngine */}
        <CodeBlock lang="typescript" title="StrategyEngine — evaluate best strategy">
{`import { StrategyEngine } from '@flowintents/solver-sdk'

const engine = new StrategyEngine()

const strategies = await engine.evaluate(intent)
// Returns Strategy[] sorted by score (index 0 = best)
// Strategy: {
//   protocol: string        // e.g. "Ankr", "AlphaYield"
//   chain: 'flow' | 'ethereum' | 'base' | 'arbitrum'
//   expectedAPY: number     // e.g. 4.2
//   confidence: number      // 0–1
//   encodedBatch: Uint8Array  // ABI-encoded StrategyStep[]
//   rationale: string
// }

const best = strategies[0]
console.log(\`Best: \${best.protocol} @ \${best.expectedAPY}% APY\`)`}
        </CodeBlock>

        {/* Executor */}
        <CodeBlock lang="typescript" title="Executor — submit bid on-chain">
{`import { Executor } from '@flowintents/solver-sdk'

const executor = new Executor(config)

// Register solver (one-time, requires ERC-8004 token on Flow EVM)
const regTxId = await executor.registerSolver()
console.log('Registered:', regTxId)

// Submit a bid
const txId = await executor.submitBid(intent, strategy)
// Internally calls submitBidV0_4.cdc with:
//   intentId, offeredAPY, agentTokenId, encodedBatch`}
        </CodeBlock>

        {/* BidBuilder */}
        <CodeBlock lang="typescript" title="BidBuilder — low-level bid args">
{`import {
  buildBidArgs,
  strategyToBidArgs,
  toUFix64,
  type BidArgs,
} from '@flowintents/solver-sdk'
import * as fcl from '@onflow/fcl'

// toUFix64: format number to exactly 8 decimal places (FCL requirement)
const apy = toUFix64(8.5)   // → "8.50000000"

// strategyToBidArgs: derive BidArgs from a Strategy
const bidArgs: BidArgs = strategyToBidArgs(intent.id, strategy, agentTokenId)
// BidArgs: { intentId, offeredAPY, agentTokenId, encodedBatch }

// buildBidArgs: produce FCL argument array for the transaction
const args = buildBidArgs(bidArgs)
// Pass to fcl.mutate({ cadence: submitBidCdc, args: () => args })`}
        </CodeBlock>

      </div>
    </>
  );
}

function SectionStrategyCatalog() {
  return (
    <>
      <SectionLabel>07 — Strategy Catalog</SectionLabel>
      <SectionHeading>Built-in strategies</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        These four strategies cover the full surface of live DeFi protocols on Flow EVM.
        Each produces an ABI-encoded <code className="text-[var(--text-secondary)]">StrategyStep[]</code> consumed
        by <code className="text-[var(--text-secondary)]">FlowIntentsComposerV5.executeStrategyWithFunds()</code>.
      </p>

      <div className="space-y-6">
        {STRATEGIES.map((s) => (
          <div key={s.id} className="border border-[var(--border)]" style={{ background: "var(--bg-card)" }}>
            {/* Header */}
            <div className="px-6 py-4 border-b border-[var(--border)] flex flex-wrap items-center gap-3">
              <Badge color={s.color}>{s.label}</Badge>
              <span className="text-sm font-semibold text-[var(--text-primary)]">{s.title}</span>
              <span className="ml-auto flex items-center gap-2">
                <Badge color="var(--text-muted)">{s.bot}</Badge>
                <Badge color={s.type === "Yield" ? "#00C566" : "#0047FF"}>{s.type}</Badge>
                <Badge color="#F5C542">{s.apy}</Badge>
              </span>
            </div>
            {/* Description */}
            <div className="px-6 py-4 border-b border-[var(--border)]">
              <p className="text-sm text-[var(--text-secondary)] leading-relaxed">{s.desc}</p>
            </div>
            {/* Code */}
            <div className="px-4 pt-0 pb-0">
              <div className="px-1 py-2 text-[10px] text-[var(--text-muted)]" style={{ fontFamily: "'Space Mono', monospace" }}>
                example usage
              </div>
              <pre
                className="pb-5 px-1 text-[11px] leading-relaxed overflow-x-auto text-[var(--text-secondary)]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                <code>{s.snippet}</code>
              </pre>
            </div>
          </div>
        ))}
      </div>

      {/* Composer interface */}
      <div className="mt-8 border border-[#00C566]/20 p-5" style={{ background: "#00C56606" }}>
        <div className="text-[10px] text-[#00C566]/60 uppercase tracking-widest mb-3" style={{ fontFamily: "'Space Mono', monospace" }}>
          FlowIntentsComposerV5 — entry point
        </div>
        <CodeBlock lang="solidity" title="FlowIntentsComposerV5.sol">
{`// Any COA can call — permissionless
function executeStrategyWithFunds(
    bytes calldata encodedBatch,  // ABI-encoded StrategyStep[]
    address recipient             // where to sweep output tokens
) external payable nonReentrant returns (bool);

struct StrategyStep {
    uint8   protocol;   // protocol identifier
    address target;     // contract to call
    bytes   callData;   // ABI-encoded function call
    uint256 value;      // FLOW (wei) to send
}

// Emits: BatchExecuted(caller, value, stepsExecuted, tokensSwept)
// Safety: snapshots balances before, sweeps only the delta to recipient`}
        </CodeBlock>
      </div>
    </>
  );
}

function SectionSubmitIntent() {
  return (
    <>
      <SectionLabel>08 — Submit an Intent</SectionLabel>
      <SectionHeading>Create your first intent</SectionHeading>
      <p className="text-[var(--text-secondary)] text-sm leading-relaxed mb-8 max-w-2xl">
        Intents are created by calling the Cadence transaction directly via Flow CLI,
        or through the frontend UI at <Link href="/app" className="text-[#0047FF] hover:text-white transition-colors">/app</Link>.
        Only the commission escrow is deposited on creation — the principal stays in your wallet
        until the winning solver executes.
      </p>

      {/* Yield intent Cadence tx */}
      <CodeBlock lang="cadence" title="createYieldIntentV0_4.cdc">
{`import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import IntentMarketplaceV0_4 from "IntentMarketplaceV0_4"

transaction(
    principalAmount: UFix64,       // e.g. 100.0 FLOW to put to work
    targetAPY: UFix64,             // e.g. 5.0 — minimum acceptable APY
    deliverySide: UInt8,           // 0 = Cadence, 1 = EVM
    deliveryAddress: String?,      // EVM address if deliverySide = 1
    durationDays: UInt64,          // e.g. 30
    expiryBlock: UInt64,           // block number after which intent expires
    commissionEscrowAmount: UFix64 // e.g. 0.05 FLOW — solver incentive
) {
    prepare(signer: auth(Storage, BorrowValue) &Account) {
        // withdraw only the commission escrow — principal stays in wallet
        let vault <- signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            )!.withdraw(amount: commissionEscrowAmount) as! @FlowToken.Vault

        let marketplace = getAccount(IntentMarketplaceV0_4.deployerAddress)
            .capabilities.borrow<&IntentMarketplaceV0_4.Marketplace>(
                IntentMarketplaceV0_4.MarketplacePublicPath
            )!

        let intentID = marketplace.createYieldIntent(
            ownerAddress:          signer.address,
            principalAmount:       principalAmount,
            targetAPY:             targetAPY,
            deliverySide:          deliverySide,
            deliveryAddress:       deliveryAddress,
            durationDays:          durationDays,
            expiryBlock:           expiryBlock,
            commissionEscrowVault: <- vault
        )
        log("Intent created: ".concat(intentID.toString()))
    }
}`}
      </CodeBlock>

      {/* CLI */}
      <div className="mt-6">
        <CodeBlock lang="bash" title="terminal — Flow CLI">
{`# Submit a yield intent via Flow CLI
flow transactions send cadence/transactions/createYieldIntentV0_4.cdc \\
  --arg UFix64:100.0 \\      # principalAmount — 100 FLOW
  --arg UFix64:5.0 \\        # targetAPY — minimum 5%
  --arg UInt8:1 \\           # deliverySide — 1 = EVM delivery
  --arg "Optional(String:0xYourEVMAddress)" \\
  --arg UInt64:30 \\         # durationDays
  --arg UInt64:99999999 \\   # expiryBlock
  --arg UFix64:0.05 \\       # commissionEscrowAmount
  --network mainnet \\
  --signer mainnet-account`}
        </CodeBlock>
      </div>

      {/* Swap intent */}
      <div className="mt-6">
        <CodeBlock lang="bash" title="terminal — swap intent">
{`# Submit a swap intent (FLOW → stgUSDC)
flow transactions send cadence/transactions/createSwapIntentV0_4.cdc \\
  --arg UFix64:50.0 \\                            # principalAmount — 50 FLOW
  --arg "String:0x1b97b49f28754e8c451bbf4d8bb4a32c9a31d7c1" \\  # tokenOut = stgUSDC
  --arg UFix64:10.0 \\                            # minAmountOut
  --arg UInt64:7 \\                               # durationDays
  --arg UInt64:99999999 \\                        # expiryBlock
  --arg UFix64:0.05 \\                            # commissionEscrowAmount
  --network mainnet \\
  --signer mainnet-account`}
        </CodeBlock>
      </div>

      {/* Select winner + execute */}
      <div className="mt-6 grid sm:grid-cols-2 gap-4">
        <CodeBlock lang="cadence" title="selectWinnerV0_4.cdc">
{`// Intent owner picks the best bid
import BidManagerV0_4 from "BidManagerV0_4"

transaction(intentID: UInt64) {
    prepare(signer: auth(Storage) &Account) {}
    execute {
        BidManagerV0_4.selectWinner(
            intentID:      intentID,
            callerAddress: signer.address
        )
    }
}`}
        </CodeBlock>

        <CodeBlock lang="cadence" title="submitBidV0_4.cdc">
{`// Solver submits a bid
import BidManagerV0_4 from "BidManagerV0_4"

transaction(
    intentID:        UInt64,
    offeredAPY:      UFix64?,
    offeredAmountOut: UFix64?,
    maxGasBid:       UFix64,
    strategy:        String,
    encodedBatch:    [UInt8]
) {
    prepare(signer: auth(Storage) &Account) {}
    execute {
        BidManagerV0_4.submitBid(
            intentID:         intentID,
            solverAddress:    signer.address,
            offeredAPY:       offeredAPY,
            offeredAmountOut: offeredAmountOut,
            maxGasBid:        maxGasBid,
            strategy:         strategy,
            encodedBatch:     encodedBatch
        )
    }
}`}
        </CodeBlock>
      </div>

      {/* CTA */}
      <div className="mt-10 border border-[#0047FF]/20 p-8" style={{ background: "#0047FF06" }}>
        <div
          className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-4"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Ready to start?
        </div>
        <h3 className="text-xl font-bold text-[var(--text-primary)] mb-3">
          Create an intent or build a solver.
        </h3>
        <p className="text-[var(--text-secondary)] text-sm mb-6 max-w-lg">
          The frontend lets you create intents with a wallet. The SDK gives you everything
          needed to build a competitive solver bot.
        </p>
        <div className="flex flex-wrap gap-3">
          <Link href="/app">
            <button
              className="px-6 py-2.5 text-sm font-medium text-white transition-opacity hover:opacity-80"
              style={{ background: "#0047FF", fontFamily: "'Space Grotesk', sans-serif" }}
            >
              Create Intent →
            </button>
          </Link>
          <Link href="/live">
            <button
              className="px-6 py-2.5 text-sm font-medium text-[var(--text-primary)] border border-[var(--border)] hover:border-[#0047FF]/40 transition-all"
              style={{ fontFamily: "'Space Grotesk', sans-serif" }}
            >
              Watch Live Feed
            </button>
          </Link>
          <Link href="/solver">
            <button
              className="px-6 py-2.5 text-sm font-medium text-[var(--text-secondary)] border border-[var(--border)] hover:border-[#00C566]/40 hover:text-[var(--text-primary)] transition-all"
              style={{ fontFamily: "'Space Grotesk', sans-serif" }}
            >
              Solver Guide
            </button>
          </Link>
        </div>
      </div>
    </>
  );
}

// ── Section renderer ──────────────────────────────────────────────────────────

function ActiveSection({ id }: { id: SectionId }) {
  switch (id) {
    case "overview":        return <SectionOverview />;
    case "architecture":    return <SectionArchitecture />;
    case "intent-types":    return <SectionIntentTypes />;
    case "contracts":       return <SectionContracts />;
    case "solver-guide":    return <SectionSolverGuide />;
    case "sdk-reference":   return <SectionSDKReference />;
    case "strategy-catalog": return <SectionStrategyCatalog />;
    case "submit-intent":   return <SectionSubmitIntent />;
    default:                return null;
  }
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function DocsPage() {
  const [activeSection, setActiveSection] = useState<SectionId>("overview");

  function handleSelect(id: SectionId) {
    setActiveSection(id);
    window.scrollTo(0, 0);
  }

  return (
    <div className="min-h-screen" style={{ background: "var(--bg-base)" }}>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">

        {/* Page header */}
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4 }}
          className="mb-14"
        >
          <div
            className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest mb-4"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Developer Documentation
          </div>
          <h1
            className="text-4xl sm:text-5xl font-bold text-[var(--text-primary)] mb-5"
            style={{ letterSpacing: "-0.03em" }}
          >
            FlowIntents Docs
          </h1>
          <p className="text-[var(--text-secondary)] text-base leading-relaxed max-w-2xl">
            Intent-based DeFi on Flow blockchain. Users declare financial goals — yield or swap —
            and autonomous solver agents compete to fulfill them on-chain.
          </p>
          <div className="flex flex-wrap gap-2 mt-5">
            <Badge color="#00C566">Flow Mainnet</Badge>
            <Badge color="#0047FF">V0_4</Badge>
            <Badge color="#F5C542">chainId 747</Badge>
            <Badge color="var(--text-secondary)">MIT License</Badge>
          </div>
        </motion.div>

        {/* Mobile nav pills */}
        <MobileNav activeSection={activeSection} onSelect={handleSelect} />

        {/* Two-column layout: sidebar + content */}
        <div className="flex gap-14">
          <Sidebar activeSection={activeSection} onSelect={handleSelect} />

          <div className="flex-1 min-w-0">
            <AnimatePresence mode="wait">
              <motion.div
                key={activeSection}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
              >
                <ActiveSection id={activeSection} />
              </motion.div>
            </AnimatePresence>
          </div>
        </div>

      </div>
    </div>
  );
}
