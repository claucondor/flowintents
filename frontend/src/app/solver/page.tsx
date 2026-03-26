"use client";

import React, { useState, useEffect, useCallback } from "react";
import { motion } from "framer-motion";
import { Clock, RefreshCw } from "lucide-react";
import { SubmitBidModal } from "@/components/solver/submit-bid-modal";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useWallet } from "@/lib/wallet-context";
import {
  getOpenIntentIds,
  getIntent,
  getBidsBySolver,
  getBidsByIds,
  type Intent,
  type Bid,
  intentTypeLabel,
} from "@/lib/flow";
import {
  formatAmount,
  type MockIntent,
} from "@/lib/utils";
import { cn } from "@/lib/utils";

// MY_BIDS is now populated from chain via getBidsBySolver

// Convert an on-chain Intent to the MockIntent shape used by SubmitBidModal
function toMockIntent(intent: Intent): MockIntent {
  const type = intentTypeLabel(intent.intentType);
  return {
    id: intent.id,
    type: type === "BRIDGE_YIELD" ? "YIELD" : type,
    amount: intent.principalAmount,
    status: (["Open", "BidSelected", "Active", "Completed", "Cancelled"][intent.status] ?? "Open") as MockIntent["status"],
    targetAPY: intent.targetAPY > 0 ? intent.targetAPY : undefined,
    minAmountOut: intent.minAmountOut ?? undefined,
    outputToken: intent.intentType === 1 ? "stgUSDC" : undefined,
    durationDays: intent.durationDays,
    createdAt: new Date(intent.createdAt * 1000),
    bids: [],
  };
}

// Estimate time remaining from expiryBlock
function timeRemainingFromBlock(expiryBlock: number, currentBlock: number): string {
  const blocksLeft = expiryBlock - currentBlock;
  if (blocksLeft <= 0) return "Expired";
  // Flow mainnet ~1 block per second
  const secondsLeft = blocksLeft;
  const hours = Math.floor(secondsLeft / 3600);
  const days = Math.floor(hours / 24);
  if (days > 0) return `${days}d ${hours % 24}h`;
  const minutes = Math.floor((secondsLeft % 3600) / 60);
  return `${hours}h ${minutes}m`;
}

export default function SolverPage() {
  const { isFlowConnected, connectFlow, flowUser } = useWallet();
  const [selectedIntent, setSelectedIntent] = useState<MockIntent | null>(null);
  const [bidModalOpen, setBidModalOpen] = useState(false);
  const [filterType, setFilterType] = useState<"ALL" | "YIELD" | "SWAP">("ALL");
  const [refreshing, setRefreshing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [allIntents, setAllIntents] = useState<MockIntent[]>([]);
  const [currentBlock, setCurrentBlock] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [myBids, setMyBids] = useState<Bid[]>([]);
  const [myBidsLoading, setMyBidsLoading] = useState(false);

  const load = useCallback(async () => {
    setRefreshing(true);
    setError(null);
    try {
      // Get current block for time-remaining calculation
      const blockRes = await fetch("https://rest-mainnet.onflow.org/v1/blocks?height=sealed");
      let block = 0;
      if (blockRes.ok) {
        const blockData = await blockRes.json();
        block = parseInt(blockData[0].header.height, 10);
        setCurrentBlock(block);
      }

      const ids = await getOpenIntentIds();
      const intents = await Promise.all(ids.map((id) => getIntent(id)));
      const valid = intents.filter(Boolean) as Intent[];
      setAllIntents(valid.map(toMockIntent));
    } catch (err) {
      console.error("Failed to load intents:", err);
      setError("Failed to load intents. Retrying...");
    } finally {
      setRefreshing(false);
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
    const interval = setInterval(load, 30_000);
    return () => clearInterval(interval);
  }, [load]);

  // Load bids for the connected solver wallet
  useEffect(() => {
    if (!flowUser?.addr) return;
    setMyBidsLoading(true);
    getBidsBySolver(flowUser.addr)
      .then((ids) => getBidsByIds(ids))
      .then(setMyBids)
      .catch(console.error)
      .finally(() => setMyBidsLoading(false));
  }, [flowUser?.addr]);

  const openIntents = allIntents.filter(
    (i) => i.status === "Open" && (filterType === "ALL" || i.type === filterType)
  );

  const handleBid = (intent: MockIntent) => {
    setSelectedIntent(intent);
    setBidModalOpen(true);
  };

  const timeRemaining = (intent: MockIntent) => {
    // If we have a current block, compute from expiryBlock; fall back to date math
    if (currentBlock > 0) {
      // We need the on-chain expiryBlock — it's stored in the MockIntent via createdAt
      // Since MockIntent doesn't carry expiryBlock, fall back to duration math
    }
    const expiry = intent.createdAt.getTime() + intent.durationDays * 24 * 60 * 60 * 1000;
    const diff = expiry - Date.now();
    if (diff <= 0) return "Expired";
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const days = Math.floor(hours / 24);
    if (days > 0) return `${days}d ${hours % 24}h`;
    return `${hours}h`;
  };

  return (
    <div className="min-h-screen py-12 px-4 sm:px-8" style={{ background: "#050509" }}>
      <div className="max-w-7xl mx-auto">
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
              Solver Dashboard
            </div>
            <div className="flex items-center gap-3">
              <h1
                className="text-3xl font-bold text-[#F5F5F0]"
                style={{ letterSpacing: "-0.02em" }}
              >
                Open Intents
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
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={load}
              className={cn(
                "p-2 border border-[#1a1a1a] text-[#666660] hover:text-[#F5F5F0] hover:border-[#0047FF]/40 transition-all",
                refreshing && "animate-spin"
              )}
              style={{ background: "#0D0D0D" }}
              title="Refresh"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
            {!isFlowConnected && (
              <Button variant="primary" size="sm" onClick={connectFlow}>
                Connect to Bid
              </Button>
            )}
          </div>
        </motion.div>

        {/* Stats bar */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.05 }}
          className="grid grid-cols-2 sm:grid-cols-4 gap-0 border border-[#1a1a1a] mb-6"
        >
          {[
            { label: "Open Intents", value: loading ? "—" : openIntents.length, color: "#0047FF" },
            {
              label: "Total FLOW",
              value: loading ? "—" : `${formatAmount(openIntents.reduce((s, i) => s + i.amount, 0))}`,
              color: "#F5F5F0",
            },
            {
              label: "Yield Intents",
              value: loading ? "—" : openIntents.filter((i) => i.type === "YIELD").length,
              color: "#00C566",
            },
            {
              label: "Swap Intents",
              value: loading ? "—" : openIntents.filter((i) => i.type === "SWAP").length,
              color: "#F5F5F0",
            },
          ].map((stat, i) => (
            <div
              key={stat.label}
              className={`p-5 ${i < 3 ? "border-r border-[#1a1a1a]" : ""}`}
              style={{ background: "#0D0D0D" }}
            >
              <div
                className="text-2xl font-bold mb-1"
                style={{ fontFamily: "'Space Mono', monospace", color: stat.color }}
              >
                {stat.value}
              </div>
              <div className="text-xs text-[#666660]">{stat.label}</div>
            </div>
          ))}
        </motion.div>

        {/* Filter bar */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="flex items-center gap-0 border-b border-[#1a1a1a] mb-6"
        >
          {(["ALL", "YIELD", "SWAP"] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilterType(f)}
              className="px-5 py-3 text-xs font-medium transition-all"
              style={{
                fontFamily: "'Space Mono', monospace",
                color: filterType === f ? "#F5F5F0" : "#666660",
                borderBottom: filterType === f ? "2px solid #0047FF" : "2px solid transparent",
                marginBottom: "-1px",
              }}
            >
              {f}
            </button>
          ))}
          <span
            className="ml-auto pr-4 text-xs text-[#666660]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {loading ? "loading..." : `${openIntents.length} intents`}
          </span>
        </motion.div>

        {/* Intents table */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12 }}
          className="mb-12"
        >
          <div className="border border-[#1a1a1a] overflow-hidden" style={{ background: "#0D0D0D" }}>
            {/* Table header */}
            <div
              className="hidden sm:grid px-6 py-3 border-b border-[#1a1a1a] text-[10px] text-[#666660] uppercase tracking-widest"
              style={{
                fontFamily: "'Space Mono', monospace",
                gridTemplateColumns: "80px 80px 1fr 1fr 80px 100px 120px",
              }}
            >
              <div>ID</div>
              <div>Type</div>
              <div>Amount</div>
              <div>Target</div>
              <div>Bids</div>
              <div>Expires</div>
              <div />
            </div>

            {/* Loading skeleton */}
            {loading ? (
              <div className="divide-y divide-[#1a1a1a]">
                {[0, 1, 2].map((i) => (
                  <div
                    key={i}
                    className="hidden sm:grid px-6 py-4 items-center"
                    style={{ gridTemplateColumns: "80px 80px 1fr 1fr 80px 100px 120px" }}
                  >
                    {[80, 60, 120, 140, 40, 80, 100].map((w, j) => (
                      <div
                        key={j}
                        className="h-4 rounded animate-pulse bg-[#1a1a1a]"
                        style={{ width: w }}
                      />
                    ))}
                  </div>
                ))}
              </div>
            ) : error ? (
              <div className="text-center py-12 text-red-400">
                <p className="text-sm font-mono">{error}</p>
              </div>
            ) : openIntents.length === 0 ? (
              <div className="text-center py-16 text-[#666660]">
                <div
                  className="text-xs mb-2 uppercase tracking-widest"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  No Results
                </div>
                <p className="text-sm">No open intents matching your filter</p>
              </div>
            ) : (
              <div>
                {openIntents.map((intent, i) => (
                  <motion.div
                    key={intent.id}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: i * 0.04 }}
                    className="hidden sm:grid px-6 py-4 border-b border-[#1a1a1a] last:border-0 hover:bg-[#0047FF]/5 transition-colors items-center group"
                    style={{
                      gridTemplateColumns: "80px 80px 1fr 1fr 80px 100px 120px",
                    }}
                  >
                    <div
                      className="text-xs text-[#666660]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      #{intent.id}
                    </div>
                    <div>
                      <Badge variant={intent.type === "YIELD" ? "green" : "blue"}>
                        {intent.type}
                      </Badge>
                    </div>
                    <div
                      className="text-sm font-medium text-[#F5F5F0]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {formatAmount(intent.amount)} FLOW
                    </div>
                    <div className="text-sm" style={{ fontFamily: "'Space Mono', monospace" }}>
                      {intent.type === "YIELD" ? (
                        <span className="text-[#00C566]">{intent.targetAPY}% APY</span>
                      ) : (
                        <span className="text-[#F5F5F0]">
                          ≥{formatAmount(intent.minAmountOut || 0)} {intent.outputToken}
                        </span>
                      )}
                    </div>
                    <div
                      className="text-xs"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {intent.bids.length > 0 ? (
                        <span className="text-[#0047FF]">
                          {intent.bids.length} bid{intent.bids.length > 1 ? "s" : ""}
                        </span>
                      ) : (
                        <span className="text-[#1a1a1a]">—</span>
                      )}
                    </div>
                    <div
                      className="flex items-center gap-1.5 text-xs text-[#666660]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      <Clock className="w-3 h-3" />
                      {timeRemaining(intent)}
                    </div>
                    <div className="flex justify-end">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handleBid(intent)}
                        className="opacity-0 group-hover:opacity-100 transition-opacity text-xs font-mono"
                      >
                        Submit Bid
                      </Button>
                    </div>
                  </motion.div>
                ))}

                {/* Mobile cards */}
                <div className="sm:hidden divide-y divide-[#1a1a1a]">
                  {openIntents.map((intent) => (
                    <div key={intent.id} className="p-4">
                      <div className="flex items-center justify-between mb-3">
                        <div className="flex items-center gap-2">
                          <span
                            className="text-xs text-[#666660]"
                            style={{ fontFamily: "'Space Mono', monospace" }}
                          >
                            #{intent.id}
                          </span>
                          <Badge variant={intent.type === "YIELD" ? "green" : "blue"}>
                            {intent.type}
                          </Badge>
                        </div>
                        <span
                          className="text-xs text-[#666660]"
                          style={{ fontFamily: "'Space Mono', monospace" }}
                        >
                          {timeRemaining(intent)}
                        </span>
                      </div>
                      <div
                        className="text-sm font-medium text-[#F5F5F0] mb-1"
                        style={{ fontFamily: "'Space Mono', monospace" }}
                      >
                        {formatAmount(intent.amount)} FLOW
                      </div>
                      <div className="flex items-center justify-between mt-3">
                        <span
                          className="text-xs"
                          style={{
                            fontFamily: "'Space Mono', monospace",
                            color: intent.type === "YIELD" ? "#00C566" : "#F5F5F0",
                          }}
                        >
                          {intent.type === "YIELD"
                            ? `${intent.targetAPY}% APY`
                            : `≥${formatAmount(intent.minAmountOut || 0)} ${intent.outputToken}`}
                        </span>
                        <Button variant="primary" size="sm" onClick={() => handleBid(intent)}>
                          Bid
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </motion.div>

        {/* My Submitted Bids */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
        >
          <div
            className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            My Submitted Bids
          </div>

          {!isFlowConnected ? (
            <div
              className="border border-[#1a1a1a] p-8 text-center text-[#666660]"
              style={{ background: "#0D0D0D" }}
            >
              <p className="text-sm mb-3">Connect your wallet to see your bids</p>
              <Button variant="primary" size="sm" onClick={connectFlow}>
                Connect Wallet
              </Button>
            </div>
          ) : myBidsLoading ? (
            <div
              className="border border-[#1a1a1a] p-8 text-center text-[#666660]"
              style={{ background: "#0D0D0D" }}
            >
              <p className="text-sm">Loading your bids...</p>
            </div>
          ) : myBids.length === 0 ? (
            <div
              className="border border-[#1a1a1a] p-8 text-center text-[#666660]"
              style={{ background: "#0D0D0D" }}
            >
              <p className="text-sm">No bids submitted yet</p>
            </div>
          ) : (
            <div
              className="border border-[#1a1a1a] overflow-hidden"
              style={{ background: "#0D0D0D" }}
            >
              <div
                className="hidden sm:grid px-6 py-3 border-b border-[#1a1a1a] text-[10px] text-[#666660] uppercase tracking-widest"
                style={{
                  fontFamily: "'Space Mono', monospace",
                  gridTemplateColumns: "60px 80px 80px 1fr 120px 100px 80px",
                }}
              >
                <div>Bid ID</div>
                <div>Intent</div>
                <div>Type</div>
                <div>Offered</div>
                <div>Status</div>
                <div>Score</div>
                <div>Gas Bid</div>
              </div>
              {myBids.map((bid) => {
                // Determine intent type label
                const intentType = bid.offeredAPY != null ? "YIELD" : "SWAP";
                const offeredStr = bid.offeredAPY != null
                  ? `${bid.offeredAPY.toFixed(2)}% APY`
                  : bid.offeredAmountOut != null
                  ? `${bid.offeredAmountOut.toFixed(4)} out`
                  : "—";
                // Find matching intent to get status cross-reference
                const matchingIntent = allIntents.find((i) => i.id === bid.intentID);
                let bidStatus = "Pending";
                if (matchingIntent) {
                  const intentStatus = matchingIntent.status;
                  if (intentStatus === "Completed" || intentStatus === "Active") {
                    // We'd need winningBidID from the intent — use allIntents source Intent
                    bidStatus = "Pending"; // default without winningBidID in MockIntent
                  }
                }
                return (
                  <div
                    key={bid.id}
                    className="hidden sm:grid px-6 py-4 border-b border-[#1a1a1a] last:border-0 items-center"
                    style={{
                      gridTemplateColumns: "60px 80px 80px 1fr 120px 100px 80px",
                    }}
                  >
                    <div
                      className="text-xs text-[#666660]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      #{bid.id}
                    </div>
                    <div
                      className="text-xs text-[#666660]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      #{bid.intentID}
                    </div>
                    <div>
                      <Badge variant={intentType === "YIELD" ? "green" : "blue"}>
                        {intentType}
                      </Badge>
                    </div>
                    <div
                      className="text-sm font-medium text-[#F5F5F0]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {offeredStr}
                    </div>
                    <div>
                      <Badge variant="yellow">{bidStatus}</Badge>
                    </div>
                    <div
                      className="text-xs text-[#00C566]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {bid.score.toFixed(4)}
                    </div>
                    <div
                      className="text-xs text-[#666660]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {bid.maxGasBid} FLOW
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </motion.div>
      </div>

      {selectedIntent && (
        <SubmitBidModal
          open={bidModalOpen}
          onClose={() => {
            setBidModalOpen(false);
            setSelectedIntent(null);
          }}
          intent={selectedIntent}
          isConnected={isFlowConnected}
          onConnectFlow={connectFlow}
        />
      )}
    </div>
  );
}
