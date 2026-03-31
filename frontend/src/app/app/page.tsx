"use client";

import React, { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CreateIntentForm } from "@/components/intents/create-intent-form";
import { IntentCard } from "@/components/intents/intent-card";
import { useWallet } from "@/lib/wallet-context";
import {
  getTotalIntentsV04,
  getIntentV04,
  getBidsForIntentV04,
  getBidV04,
  type Intent,
  intentTypeLabel,
  intentStatusLabel,
} from "@/lib/flow";
import type { MockIntent } from "@/lib/utils";

type Tab = "create" | "my-intents";

// Convert on-chain Intent to MockIntent shape used by IntentCard
function toMockIntent(intent: Intent): MockIntent {
  const type = intentTypeLabel(intent.intentType);
  return {
    id: intent.id,
    type: type === "BRIDGE_YIELD" ? "YIELD" : type,
    amount: intent.principalAmount,
    status: intentStatusLabel(intent.status) as MockIntent["status"],
    targetAPY: intent.targetAPY > 0 ? intent.targetAPY : undefined,
    minAmountOut: undefined,
    outputToken: intent.tokenOut === "0xF1815bd50389c46847f0Bda824eC8da914045D14" ? "stgUSDC"
      : intent.tokenOut === "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e" ? "WFLOW"
      : intent.intentType === 1 ? "stgUSDC" : undefined,
    durationDays: intent.durationDays,
    createdAt: new Date(intent.createdAt * 1000),
    bids: [],
  };
}

export default function AppPage() {
  const { flowUser, isFlowConnected } = useWallet();
  const [activeTab, setActiveTab] = useState<Tab>("create");
  const [intents, setIntents] = useState<MockIntent[]>([]);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);

  const loadMyIntents = useCallback(async () => {
    if (!isFlowConnected || !flowUser.addr) {
      setIntents([]);
      return;
    }
    setLoading(true);
    try {
      const total = await getTotalIntentsV04();
      if (total === 0) {
        setIntents([]);
        return;
      }
      // Fetch all intents, filter by owner
      const ids = Array.from({ length: total }, (_, i) => i);
      const allIntents = await Promise.all(ids.map((id) => getIntentV04(id)));
      const mine = (allIntents.filter(Boolean) as Intent[]).filter(
        (i) => i.intentOwner === flowUser.addr
      );
      // Load winning bid offers for BidSelected intents
      const mockIntents = await Promise.all(mine.map(async (intent) => {
        const mock = toMockIntent(intent);
        if (intent.winningBidID != null) {
          try {
            const bid = await getBidV04(intent.winningBidID);
            if (bid) {
              mock.winningOffer = bid.offeredAmountOut ?? bid.offeredAPY ?? undefined;
            }
          } catch { /* ignore */ }
        } else if (intent.status === 0) {
          // Open — check if there are bids to show count
          try {
            const bidIds = await getBidsForIntentV04(intent.id);
            mock.bids = bidIds.map((id) => ({ id, solverAddress: '', strategy: '', score: 0, gasBid: 0, createdAt: new Date() }));
          } catch { /* ignore */ }
        }
        return mock;
      }));
      setIntents(mockIntents);
    } catch (err) {
      console.error("Failed to load my intents:", err);
    } finally {
      setLoading(false);
      setLoaded(true);
    }
  }, [isFlowConnected, flowUser.addr]);

  // Load when switching to my-intents tab
  useEffect(() => {
    if (activeTab === "my-intents" && !loaded) {
      loadMyIntents();
    }
  }, [activeTab, loaded, loadMyIntents]);

  // Reload when wallet connects/disconnects
  useEffect(() => {
    setLoaded(false);
  }, [flowUser.addr]);

  const handleSelectWinner = (intentId: number) => {
    setIntents((prev) =>
      prev.map((i) => (i.id === intentId ? { ...i, status: "BidSelected" as const } : i))
    );
  };

  const tabs: { id: Tab; label: string; count?: number }[] = [
    { id: "create", label: "CREATE INTENT" },
    { id: "my-intents", label: "MY INTENTS", count: loaded ? intents.length : undefined },
  ];

  return (
    <div className="min-h-screen py-12 px-4 sm:px-8" style={{ background: "#050509" }}>
      <div className="max-w-7xl mx-auto">
        {/* Page header */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-10 flex flex-col sm:flex-row sm:items-end justify-between gap-4"
        >
          <div>
            <div
              className="text-[10px] text-[#666660] uppercase tracking-widest mb-3"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Intent Marketplace
            </div>
            <h1
              className="text-3xl font-bold text-[#F5F5F0]"
              style={{ letterSpacing: "-0.02em" }}
            >
              Create an Intent.
            </h1>
            <p className="text-sm text-[#666660] mt-1">
              Lock your FLOW, set your goal — solvers compete to get you the best outcome.
            </p>
          </div>
          {isFlowConnected && flowUser.addr && (
            <div
              className="flex items-center gap-2 px-4 py-2 border border-[#1a1a1a]"
              style={{ background: "#0D0D0D" }}
            >
              <span className="w-1.5 h-1.5 bg-[#00C566] rounded-full animate-pulse" />
              <span
                className="text-[11px] text-[#9999A0]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {flowUser.addr}
              </span>
            </div>
          )}
        </motion.div>

        {/* Tab navigation */}
        <div className="flex gap-0 border-b border-[#1a1a1a] mb-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className="relative px-6 py-3 text-xs font-medium transition-all duration-200"
              style={{
                fontFamily: "'Space Mono', monospace",
                color: activeTab === tab.id ? "#F5F5F0" : "#666660",
                borderBottom: activeTab === tab.id ? "2px solid #0047FF" : "2px solid transparent",
                marginBottom: "-1px",
              }}
            >
              {tab.label}
              {tab.count !== undefined && (
                <span
                  className="ml-2 px-1.5 py-0.5 text-[9px] border"
                  style={{
                    color: "#666660",
                    borderColor: "#1a1a1a",
                    fontFamily: "'Space Mono', monospace",
                  }}
                >
                  {tab.count}
                </span>
              )}
            </button>
          ))}
        </div>

        <AnimatePresence mode="wait">
          {activeTab === "create" ? (
            <motion.div
              key="create"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.2 }}
              className="grid lg:grid-cols-5 gap-6"
            >
              {/* Form */}
              <div className="lg:col-span-3 border border-[#1a1a1a]" style={{ background: "#0D0D0D" }}>
                <div className="px-6 pt-6 pb-4 border-b border-[#1a1a1a]">
                  <div
                    className="text-[10px] text-[#666660] uppercase tracking-widest mb-1"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    New Intent
                  </div>
                  <h2 className="text-lg font-semibold text-[#F5F5F0]">Create Intent</h2>
                </div>
                <div className="p-6">
                  <CreateIntentForm />
                </div>
              </div>

              {/* Info panel */}
              <div className="lg:col-span-2 space-y-4">
                {/* How it works */}
                <div className="border border-[#1a1a1a] p-6" style={{ background: "#0D0D0D" }}>
                  <div
                    className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    How Intents Work
                  </div>
                  <div className="space-y-5">
                    {[
                      {
                        n: "01",
                        title: "Lock your FLOW",
                        desc: "Principal + gas escrow secured in the smart contract",
                      },
                      {
                        n: "02",
                        title: "Solvers bid",
                        desc: "Registered solvers submit competitive offers with their strategy",
                      },
                      {
                        n: "03",
                        title: "Select & execute",
                        desc: "Review bids and select the best. You receive your desired result.",
                      },
                    ].map((step) => (
                      <div key={step.n} className="flex gap-4">
                        <div
                          className="text-[11px] text-[#1a1a1a] font-bold shrink-0 mt-0.5"
                          style={{ fontFamily: "'Space Mono', monospace" }}
                        >
                          {step.n}
                        </div>
                        <div>
                          <div className="text-sm font-medium text-[#F5F5F0]">{step.title}</div>
                          <div className="text-xs text-[#666660] mt-0.5 leading-relaxed">{step.desc}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Token support */}
                <div className="border border-[#1a1a1a] p-6" style={{ background: "#0D0D0D" }}>
                  <div
                    className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    Token Support
                  </div>
                  <div className="space-y-3">
                    {[
                      { symbol: "FLOW", desc: "Input token for all intents", color: "#0047FF" },
                      { symbol: "WFLOW", desc: "Wrapped FLOW on EVM", color: "#0047FF" },
                      { symbol: "stgUSDC", desc: "Stargate bridged USDC", color: "#00C566" },
                      { symbol: "ankrFLOW", desc: "Ankr liquid staked FLOW", color: "#F5F5F0" },
                    ].map((t) => (
                      <div
                        key={t.symbol}
                        className="flex items-center justify-between py-2 border-b border-[#1a1a1a] last:border-0"
                      >
                        <span
                          className="text-xs font-bold"
                          style={{ fontFamily: "'Space Mono', monospace", color: t.color }}
                        >
                          {t.symbol}
                        </span>
                        <span className="text-xs text-[#666660]">{t.desc}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="my-intents"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.2 }}
            >
              {!isFlowConnected ? (
                <div
                  className="border border-[#1a1a1a] p-16 text-center"
                  style={{ background: "#0D0D0D" }}
                >
                  <div
                    className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    Wallet Required
                  </div>
                  <h3 className="text-xl font-semibold text-[#F5F5F0] mb-2">Connect your wallet</h3>
                  <p className="text-[#666660] mb-6 text-sm">Connect your Flow wallet to see your intents</p>
                </div>
              ) : loading ? (
                <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
                  {[0, 1, 2].map((i) => (
                    <div
                      key={i}
                      className="border border-[#1a1a1a] p-6 animate-pulse"
                      style={{ background: "#0D0D0D" }}
                    >
                      <div className="h-4 bg-[#1a1a1a] rounded mb-3 w-2/3" />
                      <div className="h-6 bg-[#1a1a1a] rounded mb-2 w-1/2" />
                      <div className="h-3 bg-[#1a1a1a] rounded w-3/4" />
                    </div>
                  ))}
                </div>
              ) : intents.length === 0 ? (
                <div
                  className="border border-[#1a1a1a] p-16 text-center"
                  style={{ background: "#0D0D0D" }}
                >
                  <div
                    className="text-[10px] text-[#666660] uppercase tracking-widest mb-4"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    No Intents
                  </div>
                  <h3 className="text-xl font-semibold text-[#F5F5F0] mb-2">No intents yet</h3>
                  <p className="text-[#666660] mb-6 text-sm">Create your first intent to get started</p>
                  <button
                    onClick={() => setActiveTab("create")}
                    className="text-[#0047FF] hover:text-[#0039CC] text-sm font-medium transition-colors font-mono"
                  >
                    Create an Intent →
                  </button>
                </div>
              ) : (
                <div>
                  {/* Summary stats */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-0 border border-[#1a1a1a] mb-6">
                    {[
                      { label: "Total", value: intents.length, color: "#F5F5F0" },
                      { label: "Open", value: intents.filter((i) => i.status === "Open").length, color: "#0047FF" },
                      {
                        label: "Active",
                        value: intents.filter((i) => ["BidSelected", "Active"].includes(i.status)).length,
                        color: "#F5F5F0",
                      },
                      {
                        label: "Completed",
                        value: intents.filter((i) => i.status === "Completed").length,
                        color: "#00C566",
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
                  </div>

                  <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
                    {intents.map((intent) => (
                      <IntentCard
                        key={intent.id}
                        intent={intent}
                        onSelectWinner={handleSelectWinner}
                      />
                    ))}
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
