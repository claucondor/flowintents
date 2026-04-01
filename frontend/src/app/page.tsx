"use client";

import React, { useEffect, useState, useRef } from "react";
import Link from "next/link";
import { motion, AnimatePresence } from "framer-motion";
import { DotGrid } from "@/components/ui/dot-grid";
import { getProtocolStats, type ProtocolStats } from "@/lib/flow";

// ── Ticker ────────────────────────────────────────────────────────────────────

const TICKER_ITEMS = [
  "FLOWINTENTS PROTOCOL",
  "7 INTENTS FILLED TODAY",
  "BEST YIELD 4.2% APR",
  "POWERED BY FLOW BLOCKCHAIN",
  "SOLVERS COMPETING NOW",
  "0.89 FLOW AVG GAS SAVED",
  "PUNCHSWAP · ANKR · MORE FINANCE",
  "NON-CUSTODIAL · TRUSTLESS",
];

function Ticker() {
  const content = TICKER_ITEMS.join(" · ") + " · ";
  return (
    <div
      className="w-full overflow-hidden border-b border-[var(--border)]"
      style={{ height: "36px", background: "var(--bg-base)" }}
    >
      <div className="flex animate-marquee whitespace-nowrap" style={{ width: "200%" }}>
        {[content, content].map((text, i) => (
          <span
            key={i}
            className="text-[10px] text-[var(--text-secondary)] leading-[36px] px-4"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {text}
          </span>
        ))}
      </div>
    </div>
  );
}

// ── CountUp ───────────────────────────────────────────────────────────────────

function CountUp({ target, duration = 1200, suffix = "" }: { target: number; duration?: number; suffix?: string; }) {
  const [count, setCount] = useState(0)
  const ref = useRef<HTMLDivElement>(null)
  const started = useRef(false)

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !started.current) {
          started.current = true
          const start = Date.now()
          const tick = () => {
            const elapsed = Date.now() - start
            const progress = Math.min(elapsed / duration, 1)
            const eased = 1 - Math.pow(1 - progress, 3)
            setCount(Math.round(eased * target))
            if (progress < 1) requestAnimationFrame(tick)
          }
          requestAnimationFrame(tick)
        }
      },
      { threshold: 0.5 }
    )
    if (ref.current) observer.observe(ref.current)
    return () => observer.disconnect()
  }, [target, duration])

  return <div ref={ref}>{count}{suffix}</div>
}

// ── Typewriter ────────────────────────────────────────────────────────────────

const PHRASES = [
  "Express what you want. Solvers compete to get it.",
  "Yield 4.2% APR on your FLOW with one click.",
  "Swap FLOW for stgUSDC at the best available rate.",
]

function Typewriter() {
  const [phraseIdx, setPhraseIdx] = useState(0)
  const [displayed, setDisplayed] = useState("")
  const [typing, setTyping] = useState(true)

  useEffect(() => {
    const phrase = PHRASES[phraseIdx]
    if (typing) {
      if (displayed.length < phrase.length) {
        const t = setTimeout(() => setDisplayed(phrase.slice(0, displayed.length + 1)), 40)
        return () => clearTimeout(t)
      } else {
        const t = setTimeout(() => setTyping(false), 2000)
        return () => clearTimeout(t)
      }
    } else {
      if (displayed.length > 0) {
        const t = setTimeout(() => setDisplayed(displayed.slice(0, -1)), 20)
        return () => clearTimeout(t)
      } else {
        setPhraseIdx((i) => (i + 1) % PHRASES.length)
        setTyping(true)
      }
    }
  }, [displayed, typing, phraseIdx])

  return (
    <p className="text-base text-[var(--text-secondary)] leading-relaxed max-w-md h-12">
      {displayed}
      <span className="inline-block w-0.5 h-4 bg-[#0047FF] ml-0.5 animate-pulse" />
    </p>
  )
}

// ── Hero Demo ─────────────────────────────────────────────────────────────────

type DemoStep = 0 | 1 | 2;

const DEMO_DURATION = 1200; // ms per step

function HeroDemo() {
  const [step, setStep] = useState<DemoStep>(0);

  useEffect(() => {
    const timers = [
      setTimeout(() => setStep(1), DEMO_DURATION),
      setTimeout(() => setStep(2), DEMO_DURATION * 2.2),
      setTimeout(() => { setStep(0); }, DEMO_DURATION * 3.8),
    ];
    const loop = setInterval(() => {
      setStep(0);
      setTimeout(() => setStep(1), DEMO_DURATION);
      setTimeout(() => setStep(2), DEMO_DURATION * 2.2);
    }, DEMO_DURATION * 4.5);

    return () => {
      timers.forEach(clearTimeout);
      clearInterval(loop);
    };
  }, []);

  return (
    <div className="relative w-[340px] h-[260px]">
      {/* Card 1 — Intent */}
      <AnimatePresence>
        {step >= 0 && (
          <motion.div
            key="intent"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4 }}
            className="absolute top-0 left-0 w-full border border-[var(--border)] p-4"
            style={{ background: "var(--bg-card)" }}
          >
            <div
              className="text-[9px] text-[var(--text-secondary)] uppercase tracking-widest mb-3"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              LOT #2847 · SWAP INTENT
            </div>
            <div
              className="text-sm text-[var(--text-primary)] font-medium mb-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              SWAP 0.2 FLOW → stgUSDC
            </div>
            <div className="text-[11px] text-[var(--text-secondary)]">Min: 3,000 units · 30d duration</div>
            <div className="mt-3 pt-3 border-t border-[var(--border)] flex items-center gap-2">
              <span className="w-1.5 h-1.5 bg-[#0047FF] rounded-full animate-pulse" />
              <span
                className="text-[10px] text-[#0047FF]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                AWAITING BIDS
              </span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Card 2 — Bid */}
      <AnimatePresence>
        {step >= 1 && (
          <motion.div
            key="bid"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.35 }}
            className="absolute top-[110px] left-[24px] w-[300px] border border-[#0047FF]/40 p-4"
            style={{ background: "var(--bg-card)" }}
          >
            <div
              className="text-[9px] text-[#0047FF] uppercase tracking-widest mb-2"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              BID RECEIVED
            </div>
            <div className="flex items-center justify-between">
              <div>
                <div
                  className="text-xs text-[var(--text-primary)] font-medium"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  Solver A
                </div>
                <div className="text-[11px] text-[var(--text-secondary)]">via PunchSwap</div>
              </div>
              <div
                className="text-sm text-[var(--text-primary)] font-bold"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                3,191 stgUSDC
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Card 3 — Executed */}
      <AnimatePresence>
        {step >= 2 && (
          <motion.div
            key="executed"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.3 }}
            className="absolute top-[195px] left-[48px] w-[280px] border border-[#00C566]/40 px-4 py-3 flex items-center justify-between"
            style={{ background: "var(--bg-card)" }}
          >
            <div className="flex items-center gap-2">
              <span className="text-[#00C566] text-sm">✓</span>
              <span
                className="text-[11px] text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                EXECUTED · 3,191 stgUSDC
              </span>
            </div>
            <span
              className="text-[9px] text-[var(--text-secondary)]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              #146,442,801
            </span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────

const sectionReveal = {
  initial: { opacity: 0, y: 24 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: "-80px" },
  transition: { duration: 0.5, ease: [0.22, 1, 0.36, 1] },
} as const;

export default function HomePage() {
  const [stats, setStats] = useState<ProtocolStats>({
    totalIntents: 0,
    openIntents: 0,
    executedIntents: 0,
    totalVolumeFlow: 0,
  });

  useEffect(() => {
    getProtocolStats().then(setStats).catch(console.error);
  }, []);

  return (
    <div className="min-h-screen" style={{ background: "var(--bg-base)" }}>
      {/* Ticker */}
      <Ticker />

      {/* Hero */}
      <section className="relative min-h-[calc(100vh-36px)] flex flex-col justify-center px-6 sm:px-12 lg:px-20 py-20 overflow-hidden">
        <DotGrid />
        <div className="relative z-10">
          {/* Top-left version tag */}
          <div
            className="mb-12 text-[11px] text-[var(--text-secondary)]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            v0.3 · Flow Mainnet · Live
          </div>

          <div className="flex flex-col lg:flex-row items-start justify-between gap-16">
            {/* Left — headline */}
            <div className="flex-1 max-w-2xl">
              <motion.h1
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
                className="font-bold leading-none tracking-tight mb-8"
                style={{
                  fontSize: "clamp(56px, 8vw, 96px)",
                  letterSpacing: "-0.03em",
                  color: "var(--text-primary)",
                }}
              >
                The Intent
                <br />
                Layer for
                <br />
                <span style={{ color: "#0047FF" }}>Flow.</span>
              </motion.h1>

              <motion.div
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.2, duration: 0.5 }}
                className="mb-10"
              >
                <Typewriter />
              </motion.div>

              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.35, duration: 0.5 }}
                className="flex flex-col sm:flex-row gap-3"
              >
                <Link href="/app">
                  <button
                    className="px-8 py-3 text-sm font-medium text-white transition-all duration-150 hover:bg-[#0039CC] active:bg-[#002FA6]"
                    style={{
                      background: "#0047FF",
                      fontFamily: "'Space Grotesk', sans-serif",
                    }}
                  >
                    Create Intent
                  </button>
                </Link>
                <button
                  onClick={() => {
                    document.getElementById("how-it-works")?.scrollIntoView({ behavior: "smooth" });
                  }}
                  className="px-8 py-3 text-sm font-medium text-[var(--text-primary)] border border-[var(--border)] hover:border-[#0047FF] hover:text-[#0047FF] transition-all duration-150"
                  style={{ fontFamily: "'Space Grotesk', sans-serif" }}
                >
                  View Protocol
                </button>
              </motion.div>
            </div>

            {/* Right — demo */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 0.5, duration: 0.6 }}
              className="flex-shrink-0"
            >
              <div
                className="text-[9px] text-[var(--text-secondary)] uppercase tracking-widest mb-4"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Live demo · Intent lifecycle
              </div>
              <HeroDemo />
            </motion.div>
          </div>
        </div>
      </section>

      {/* Separator */}
      <div className="border-t border-[var(--border)]" />

      {/* Stats bar */}
      <section className="py-12 px-6 sm:px-12">
        <motion.div {...sectionReveal} className="max-w-5xl mx-auto grid grid-cols-2 sm:grid-cols-4 gap-0 border border-[var(--border)]">
          {/* Active Intents */}
          <div className="p-6 border-r border-[var(--border)]">
            <div
              className="text-3xl sm:text-4xl font-bold text-[var(--text-primary)] mb-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              <CountUp target={stats.openIntents} />
            </div>
            <div className="text-xs text-[var(--text-secondary)]">Active Intents</div>
          </div>
          {/* Total Volume */}
          <div className="p-6 border-r border-[var(--border)]">
            <div
              className="text-3xl sm:text-4xl font-bold text-[var(--text-primary)] mb-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              <CountUp target={Math.round(stats.totalVolumeFlow)} suffix=" FLOW" />
            </div>
            <div className="text-xs text-[var(--text-secondary)]">Total Volume (FLOW)</div>
          </div>
          {/* Best Yield — hardcoded, no on-chain source yet */}
          <div className="p-6 border-r border-[var(--border)] border-t sm:border-t-0 border-[var(--border)]">
            <div
              className="text-3xl sm:text-4xl font-bold text-[var(--text-primary)] mb-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              <CountUpDecimal target={42} display={(v) => `${Math.floor(v / 10)}.${v % 10}%`} />
            </div>
            <div className="text-xs text-[var(--text-secondary)]">Best Yield Today</div>
          </div>
          {/* Intents Executed */}
          <div className="p-6 border-t sm:border-t-0 border-[var(--border)]">
            <div
              className="text-3xl sm:text-4xl font-bold text-[var(--text-primary)] mb-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              <CountUp target={stats.executedIntents} />
            </div>
            <div className="text-xs text-[var(--text-secondary)]">Intents Executed</div>
          </div>
        </motion.div>
      </section>

      {/* Separator */}
      <div className="border-t border-[var(--border)]" />

      {/* How it works */}
      <section id="how-it-works" className="py-20 px-6 sm:px-12">
        <div className="max-w-5xl mx-auto">
          <motion.div {...sectionReveal}>
            <div
              className="text-[10px] text-[var(--text-secondary)] uppercase tracking-widest mb-12"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Protocol Mechanics
            </div>

            <div className="grid sm:grid-cols-3 gap-0 border border-[var(--border)]">
              {[
                {
                  num: "01",
                  title: "Create\nan Intent",
                  desc: "Tell us what you want. Yield or swap. Your tokens lock in the smart contract.",
                },
                {
                  num: "02",
                  title: "Solvers\nCompete",
                  desc: "Multiple solvers analyze your intent and submit competitive bids.",
                },
                {
                  num: "03",
                  title: "Receive\nBest Rate",
                  desc: "Execute the winning bid. Tokens arrive exactly as specified.",
                },
              ].map((step, i) => (
                <div
                  key={step.num}
                  className={`p-8 ${i < 2 ? "border-r border-[var(--border)]" : ""}`}
                >
                  <div
                    className="text-5xl font-bold text-[var(--border)] mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    {step.num}
                  </div>
                  <div className="border-t border-[var(--border)] mb-4" />
                  <div
                    className="text-xl font-semibold text-[var(--text-primary)] mb-3 whitespace-pre-line"
                    style={{ lineHeight: 1.3 }}
                  >
                    {step.title}
                  </div>
                  <p className="text-base text-[var(--text-secondary)] leading-relaxed">{step.desc}</p>
                </div>
              ))}
            </div>
          </motion.div>
        </div>
      </section>

      {/* Separator */}
      <div className="border-t border-[var(--border)]" />

      {/* Strategies */}
      <section className="py-20 px-6 sm:px-12">
        <div className="max-w-5xl mx-auto">
          <motion.div {...sectionReveal}>
            <div
              className="text-[10px] text-[var(--text-secondary)] uppercase tracking-widest mb-4"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Supported Strategies
            </div>
            <h2 className="text-3xl font-bold text-[var(--text-primary)] mb-12" style={{ letterSpacing: "-0.02em" }}>
              What you can do today.
            </h2>

            <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-0 border border-[var(--border)]">
              {[
                {
                  from: "FLOW",
                  to: "WFLOW",
                  icon: "⬡",
                  label: "Wrap",
                  desc: "Wrap FLOW to WFLOW on EVM layer",
                  rate: "1:1",
                  rateLabel: "No slippage",
                },
                {
                  from: "FLOW",
                  to: "stgUSDC",
                  icon: "◈",
                  label: "PunchSwap",
                  desc: "Swap FLOW for stgUSDC via AMM",
                  rate: "~$0.32",
                  rateLabel: "per FLOW",
                },
                {
                  from: "FLOW",
                  to: "ankrFLOW",
                  icon: "⬟",
                  label: "Ankr Stake",
                  desc: "Liquid staking via Ankr protocol",
                  rate: "4.2%",
                  rateLabel: "APR",
                },
                {
                  from: "FLOW",
                  to: "mFlowWFLOW",
                  icon: "◆",
                  label: "MORE Finance",
                  desc: "Yield farming on MORE Finance",
                  rate: "3.8%",
                  rateLabel: "APY",
                },
              ].map((s, i) => (
                <div
                  key={s.to}
                  className={`group p-6 hover:bg-[#0047FF]/5 transition-colors cursor-pointer ${i < 3 ? "border-r border-[var(--border)]" : ""}`}
                >
                  <div
                    className="text-2xl text-[#0047FF] mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    {s.icon}
                  </div>
                  <div
                    className="text-xs text-[var(--text-secondary)] mb-1"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    {s.from} → {s.to}
                  </div>
                  <div className="text-sm font-semibold text-[var(--text-primary)] mb-2">{s.label}</div>
                  <p className="text-base text-[var(--text-secondary)] mb-4 leading-relaxed">{s.desc}</p>
                  <div className="border-t border-[var(--border)] pt-3 flex items-baseline gap-1">
                    <span
                      className="text-base font-bold text-[var(--text-primary)]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {s.rate}
                    </span>
                    <span className="text-[10px] text-[var(--text-secondary)]">{s.rateLabel}</span>
                  </div>
                  <div className="mt-3 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                    <Link href="/app" className="text-[10px] text-[#0047FF] font-mono hover:underline">
                      Create Intent →
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          </motion.div>
        </div>
      </section>

      {/* Separator */}
      <div className="border-t border-[var(--border)]" />

      {/* For Solvers */}
      <section
        className="py-20 px-6 sm:px-12"
        style={{ background: "#0047FF08" }}
      >
        <div className="max-w-5xl mx-auto">
          <motion.div {...sectionReveal}>
            <div className="grid lg:grid-cols-2 gap-12 items-start">
              <div>
                <div
                  className="text-[10px] text-[#0047FF] uppercase tracking-widest mb-6"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  For Solvers
                </div>
                <h2
                  className="text-4xl font-bold text-[var(--text-primary)] mb-4"
                  style={{ letterSpacing: "-0.02em", lineHeight: 1.2 }}
                >
                  Build a solver.
                  <br />
                  Earn fees on every
                  <br />
                  intent you win.
                </h2>
                <p className="text-[var(--text-secondary)] text-base leading-relaxed mb-8 max-w-sm">
                  Register as a solver, poll open intents, and submit competitive bids. The winning solver
                  earns the gas escrow fee on every successful execution.
                </p>
                <Link href="/solver">
                  <button
                    className="px-6 py-3 text-sm font-medium text-[var(--text-primary)] border border-[#0047FF]/40 hover:border-[#0047FF] hover:bg-[#0047FF]/10 transition-all duration-150"
                    style={{ fontFamily: "'Space Grotesk', sans-serif" }}
                  >
                    Read Solver Docs →
                  </button>
                </Link>
              </div>

              <div className="border border-[var(--border)]" style={{ background: "var(--bg-card)" }}>
                <div className="px-4 py-2 border-b border-[var(--border)] flex items-center gap-2">
                  <span className="w-2.5 h-2.5 rounded-full bg-red-500/50" />
                  <span className="w-2.5 h-2.5 rounded-full bg-yellow-500/50" />
                  <span className="w-2.5 h-2.5 rounded-full bg-[#00C566]/50" />
                  <span
                    className="ml-2 text-[10px] text-[var(--text-secondary)]"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    solver.ts
                  </span>
                </div>
                <pre
                  className="p-5 text-[11px] leading-relaxed overflow-x-auto"
                  style={{
                    fontFamily: "'Space Mono', monospace",
                    color: "var(--text-primary)",
                  }}
                >
                  <code>{`import { FlowIntentsClient } from '@flowintents/sdk'

const client = new FlowIntentsClient()
const intents = await client.getOpenIntents()

// bid on every swap intent
for (const intent of intents
  .filter(i => i.type === 'Swap')) {
  await client.submitBid({
    intentID: intent.id,
    offeredAmountOut: await quote(intent),
    strategy: 'PunchSwap/FLOW-USDC',
    gasBid: 0.01,
  })
}`}</code>
                </pre>
              </div>
            </div>
          </motion.div>
        </div>
      </section>

      {/* Separator */}
      <div className="border-t border-[var(--border)]" />

      {/* Footer */}
      <footer className="py-12 px-6 sm:px-12">
        <div className="max-w-5xl mx-auto flex flex-col sm:flex-row items-start sm:items-center justify-between gap-8">
          <div>
            <div
              className="text-sm font-bold tracking-widest text-[var(--text-primary)] mb-2"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              FLOWINTENTS
            </div>
            <div className="text-xs text-[var(--text-secondary)]">
              Deployed on Flow Mainnet · Contract: 0xc65395858a38d8ff
            </div>
          </div>

          <div className="flex items-center gap-8">
            <Link href="/app" className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors font-mono">
              App
            </Link>
            <Link href="/solver" className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors font-mono">
              Solver
            </Link>
            <a
              href="https://github.com/your-repo"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors font-mono"
            >
              GitHub
            </a>
          </div>
        </div>
        <div className="max-w-5xl mx-auto mt-8 pt-8 border-t border-[var(--border)]">
          <p
            className="text-[10px] text-[var(--text-secondary)]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            © 2026 FlowIntents · Built for HackaFlow 2026
          </p>
        </div>
      </footer>
    </div>
  );
}

// ── CountUpDecimal helper ─────────────────────────────────────────────────────

function CountUpDecimal({ target, display, duration = 1200 }: { target: number; display: (v: number) => string; duration?: number }) {
  const [count, setCount] = useState(0)
  const ref = useRef<HTMLDivElement>(null)
  const started = useRef(false)

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !started.current) {
          started.current = true
          const start = Date.now()
          const tick = () => {
            const elapsed = Date.now() - start
            const progress = Math.min(elapsed / duration, 1)
            const eased = 1 - Math.pow(1 - progress, 3)
            setCount(Math.round(eased * target))
            if (progress < 1) requestAnimationFrame(tick)
          }
          requestAnimationFrame(tick)
        }
      },
      { threshold: 0.5 }
    )
    if (ref.current) observer.observe(ref.current)
    return () => observer.disconnect()
  }, [target, duration])

  return <div ref={ref}>{display(count)}</div>
}
