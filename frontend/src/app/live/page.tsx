"use client";

import React, { useState, useEffect, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { RefreshCw, ExternalLink } from "lucide-react";
import { getRecentEvents, type LiveEvent, type LiveEventType } from "@/lib/flow";
import { cn } from "@/lib/utils";

// ── Config ────────────────────────────────────────────────────────────────────

const POLL_INTERVAL_MS = 15_000;
const FLOW_SCAN = "https://www.flowscan.io/tx";

// ── Event display helpers ─────────────────────────────────────────────────────

const EVENT_META: Record<
  LiveEventType,
  { label: string; color: string; dot: string; bg: string }
> = {
  IntentCreated:   { label: "INTENT",   color: "#0047FF", dot: "#0047FF", bg: "rgba(0,71,255,0.07)" },
  BidSubmitted:    { label: "BID",       color: "#F5F5F0", dot: "#666660", bg: "rgba(255,255,255,0.03)" },
  WinnerSelected:  { label: "WINNER",    color: "#F5C542", dot: "#F5C542", bg: "rgba(245,197,66,0.07)" },
  IntentCompleted: { label: "EXECUTED",  color: "#00C566", dot: "#00C566", bg: "rgba(0,197,102,0.07)" },
  IntentCancelled: { label: "CANCELLED", color: "#FF4444", dot: "#FF4444", bg: "rgba(255,68,68,0.05)" },
};

function shortAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function shortTx(tx: string): string {
  if (!tx || tx.length < 12) return tx;
  return `${tx.slice(0, 8)}…`;
}

function fmtFlow(val: number | undefined | null): string {
  if (val == null) return "—";
  return val.toFixed(val < 1 ? 4 : 2);
}

function blocksAgo(eventBlock: number, currentBlock: number): string {
  const diff = currentBlock - eventBlock;
  if (diff <= 0) return "just now";
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}

function describeEvent(evt: LiveEvent): { title: string; detail: string } {
  const d = evt.data;
  switch (evt.eventType) {
    case "IntentCreated":
      return {
        title: `Intent #${d.id ?? "?"} — ${fmtFlow(d.principalAmount)} FLOW`,
        detail: d.targetAPY > 0
          ? `${d.targetAPY?.toFixed(1)}% APY · ${d.durationDays}d · ${d.principalSide === 0 ? "Cadence" : "EVM"}`
          : `Swap · ${d.durationDays}d`,
      };
    case "BidSubmitted":
      return {
        title: `Bid #${d.bidID ?? "?"} on Intent #${d.intentID ?? "?"}`,
        detail: d.offeredAPY != null
          ? `${fmtFlow(d.offeredAPY)}% APY · score ${d.score?.toFixed(3) ?? "—"} · gas ${fmtFlow(d.maxGasBid)} FLOW`
          : `amountOut ${fmtFlow(d.offeredAmountOut)} · score ${d.score?.toFixed(3) ?? "—"}`,
      };
    case "WinnerSelected":
      return {
        title: `Winner on Intent #${d.intentID ?? "?"}`,
        detail: `Bid #${d.winningBidID ?? "?"} · Solver ${shortAddr(d.solverAddress ?? "")}`,
      };
    case "IntentCompleted":
      return {
        title: `Intent #${d.id ?? "?"} Executed`,
        detail: `Owner ${shortAddr(d.owner ?? "")} · ${fmtFlow(d.finalAmount)} FLOW out`,
      };
    case "IntentCancelled":
      return {
        title: `Intent #${d.id ?? "?"} Cancelled`,
        detail: `Owner ${shortAddr(d.owner ?? "")} · ${fmtFlow(d.returnedAmount)} FLOW returned`,
      };
  }
}

// ── Filter type ───────────────────────────────────────────────────────────────

type FilterType = "ALL" | "INTENTS" | "BIDS" | "EXECUTED";

const FILTER_MAP: Record<FilterType, LiveEventType[]> = {
  ALL:      ["IntentCreated","BidSubmitted","WinnerSelected","IntentCompleted","IntentCancelled"],
  INTENTS:  ["IntentCreated","IntentCancelled"],
  BIDS:     ["BidSubmitted","WinnerSelected"],
  EXECUTED: ["IntentCompleted"],
};

// ── Page ──────────────────────────────────────────────────────────────────────

export default function LivePage() {
  const [events, setEvents] = useState<LiveEvent[]>([]);
  const [currentBlock, setCurrentBlock] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filter, setFilter] = useState<FilterType>("ALL");
  const [newIds, setNewIds] = useState<Set<string>>(new Set());
  const seenIds = useRef<Set<string>>(new Set());
  const lastPollBlock = useRef(0);

  const load = useCallback(async (isManual = false) => {
    if (isManual) setRefreshing(true);
    try {
      const blockRes = await fetch("https://rest-mainnet.onflow.org/v1/blocks?height=sealed");
      let block = currentBlock;
      if (blockRes.ok) {
        const bd = await blockRes.json();
        block = parseInt(bd[0].header.height, 10);
        setCurrentBlock(block);
      }

      // On subsequent polls, only look at new blocks
      const lookback = lastPollBlock.current > 0
        ? Math.max(100, block - lastPollBlock.current + 10)
        : 1000;
      lastPollBlock.current = block;

      const fresh = await getRecentEvents(lookback);

      setEvents((prev) => {
        // Merge: new events first, deduplicate by id
        const prevMap = new Map(prev.map((e) => [e.id, e]));
        const freshNew: LiveEvent[] = [];
        for (const e of fresh) {
          if (!seenIds.current.has(e.id)) {
            freshNew.push(e);
            seenIds.current.add(e.id);
          }
          prevMap.set(e.id, e);
        }
        if (freshNew.length > 0) {
          setNewIds(new Set(freshNew.map((e) => e.id)));
          setTimeout(() => setNewIds(new Set()), 2000);
        }
        return Array.from(prevMap.values())
          .sort((a, b) => b.blockHeight - a.blockHeight)
          .slice(0, 200); // keep last 200
      });
    } catch (err) {
      console.error("Live feed error:", err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [currentBlock]);

  useEffect(() => {
    load();
    const t = setInterval(() => load(), POLL_INTERVAL_MS);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const filtered = events.filter((e) => FILTER_MAP[filter].includes(e.eventType));

  // Stats
  const stats = {
    total: events.length,
    bids: events.filter((e) => e.eventType === "BidSubmitted").length,
    winners: events.filter((e) => e.eventType === "WinnerSelected").length,
    executed: events.filter((e) => e.eventType === "IntentCompleted").length,
    intents: events.filter((e) => e.eventType === "IntentCreated").length,
    volume: events
      .filter((e) => e.eventType === "IntentCreated")
      .reduce((s, e) => s + (e.data.principalAmount ?? 0), 0),
  };

  return (
    <div className="min-h-screen py-12 px-4 sm:px-8" style={{ background: "#050509" }}>
      <div className="max-w-5xl mx-auto">

        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-10"
        >
          <div>
            <div
              className="text-[10px] text-[#666660] uppercase tracking-widest mb-3"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Protocol Activity
            </div>
            <div className="flex items-center gap-3">
              <h1
                className="text-3xl font-bold text-[#F5F5F0]"
                style={{ letterSpacing: "-0.02em" }}
              >
                Live Feed
              </h1>
              <div className="flex items-center gap-1.5">
                <span className="w-2 h-2 bg-[#00C566] rounded-full animate-pulse" />
                <span
                  className="text-[10px] text-[#00C566]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  LIVE
                </span>
              </div>
            </div>
            {currentBlock > 0 && (
              <div
                className="text-[10px] text-[#333330] mt-1"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Block {currentBlock.toLocaleString()} · polls every {POLL_INTERVAL_MS / 1000}s
              </div>
            )}
          </div>
          <button
            onClick={() => load(true)}
            className={cn(
              "p-2 border border-[#1a1a1a] text-[#666660] hover:text-[#F5F5F0] hover:border-[#0047FF]/40 transition-all",
              refreshing && "animate-spin"
            )}
            style={{ background: "#0D0D0D" }}
            title="Refresh"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </motion.div>

        {/* Stats bar */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.05 }}
          className="grid grid-cols-3 sm:grid-cols-6 gap-0 border border-[#1a1a1a] mb-6"
        >
          {[
            { label: "Events",   value: loading ? "—" : stats.total,              color: "#F5F5F0" },
            { label: "Intents",  value: loading ? "—" : stats.intents,            color: "#0047FF" },
            { label: "Bids",     value: loading ? "—" : stats.bids,               color: "#F5F5F0" },
            { label: "Winners",  value: loading ? "—" : stats.winners,            color: "#F5C542" },
            { label: "Executed", value: loading ? "—" : stats.executed,           color: "#00C566" },
            { label: "Volume",   value: loading ? "—" : `${fmtFlow(stats.volume)}`, color: "#F5F5F0" },
          ].map((s, i) => (
            <div
              key={s.label}
              className={`p-4 ${i < 5 ? "border-r border-[#1a1a1a]" : ""}`}
              style={{ background: "#0D0D0D" }}
            >
              <div
                className="text-xl font-bold mb-0.5 tabular-nums"
                style={{ fontFamily: "'Space Mono', monospace", color: s.color }}
              >
                {s.value}
              </div>
              <div className="text-[10px] text-[#666660] uppercase tracking-wide">{s.label}</div>
            </div>
          ))}
        </motion.div>

        {/* Filter tabs */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="flex items-center gap-0 border-b border-[#1a1a1a] mb-6"
        >
          {(["ALL", "INTENTS", "BIDS", "EXECUTED"] as FilterType[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className="px-5 py-3 text-xs font-medium transition-all"
              style={{
                fontFamily: "'Space Mono', monospace",
                color: filter === f ? "#F5F5F0" : "#666660",
                borderBottom: filter === f ? "2px solid #0047FF" : "2px solid transparent",
                marginBottom: "-1px",
              }}
            >
              {f}
            </button>
          ))}
          <span
            className="ml-auto pr-4 text-[10px] text-[#333330]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {loading ? "loading…" : `${filtered.length} events`}
          </span>
        </motion.div>

        {/* Feed */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12 }}
        >
          {loading ? (
            <div className="border border-[#1a1a1a]" style={{ background: "#0D0D0D" }}>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="px-6 py-4 border-b border-[#1a1a1a] last:border-0">
                  <div className="flex items-start gap-4">
                    <div className="w-16 h-4 bg-[#1a1a1a] rounded animate-pulse shrink-0 mt-0.5" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 bg-[#1a1a1a] rounded animate-pulse w-2/3" />
                      <div className="h-3 bg-[#1a1a1a] rounded animate-pulse w-1/2" />
                    </div>
                    <div className="w-20 h-3 bg-[#1a1a1a] rounded animate-pulse shrink-0" />
                  </div>
                </div>
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div
              className="border border-[#1a1a1a] p-16 text-center"
              style={{ background: "#0D0D0D" }}
            >
              <div
                className="text-[10px] text-[#666660] uppercase tracking-widest mb-3"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                No Activity
              </div>
              <p className="text-sm text-[#444440]">
                No events found in the last ~1000 blocks
              </p>
            </div>
          ) : (
            <div className="border border-[#1a1a1a] overflow-hidden" style={{ background: "#0D0D0D" }}>
              <AnimatePresence initial={false}>
                {filtered.map((evt) => {
                  const meta = EVENT_META[evt.eventType];
                  const { title, detail } = describeEvent(evt);
                  const isNew = newIds.has(evt.id);

                  return (
                    <motion.div
                      key={evt.id}
                      initial={isNew ? { opacity: 0, x: -8 } : false}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ duration: 0.25 }}
                      className="px-6 py-4 border-b border-[#1a1a1a] last:border-0 group transition-colors"
                      style={{
                        background: isNew ? meta.bg : undefined,
                      }}
                    >
                      <div className="flex items-start gap-4">
                        {/* Type badge */}
                        <div className="shrink-0 flex items-center gap-2 pt-0.5 w-28">
                          <span
                            className="w-1.5 h-1.5 rounded-full shrink-0"
                            style={{ background: meta.dot }}
                          />
                          <span
                            className="text-[10px] font-bold tracking-wider"
                            style={{
                              fontFamily: "'Space Mono', monospace",
                              color: meta.color,
                            }}
                          >
                            {meta.label}
                          </span>
                        </div>

                        {/* Content */}
                        <div className="flex-1 min-w-0">
                          <div
                            className="text-sm font-medium text-[#F5F5F0] truncate"
                            style={{ fontFamily: "'Space Mono', monospace" }}
                          >
                            {title}
                          </div>
                          <div className="text-xs text-[#666660] mt-0.5 truncate">
                            {detail}
                          </div>
                        </div>

                        {/* Right meta */}
                        <div className="shrink-0 text-right">
                          <div
                            className="text-[10px] text-[#444440]"
                            style={{ fontFamily: "'Space Mono', monospace" }}
                          >
                            {currentBlock > 0 ? blocksAgo(evt.blockHeight, currentBlock) : `#${evt.blockHeight}`}
                          </div>
                          <a
                            href={`${FLOW_SCAN}/${evt.transactionId}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1 text-[10px] text-[#333330] hover:text-[#0047FF] transition-colors mt-0.5"
                            style={{ fontFamily: "'Space Mono', monospace" }}
                          >
                            {shortTx(evt.transactionId)}
                            <ExternalLink className="w-2.5 h-2.5" />
                          </a>
                        </div>
                      </div>
                    </motion.div>
                  );
                })}
              </AnimatePresence>
            </div>
          )}
        </motion.div>

        {/* Footer note */}
        {!loading && events.length > 0 && (
          <div
            className="text-center mt-6 text-[10px] text-[#2a2a2a]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Showing last ~1000 blocks · refreshes every {POLL_INTERVAL_MS / 1000}s
          </div>
        )}
      </div>
    </div>
  );
}
