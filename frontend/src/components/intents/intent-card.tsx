"use client";

import React, { useState } from "react";
import * as fcl from "@onflow/fcl";
import { Clock } from "lucide-react";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { BidComparisonModal } from "./bid-comparison-modal";
import { type MockIntent, formatAmount } from "@/lib/utils";
import { EXECUTE_INTENT_V04_TX } from "@/lib/cadence";

interface IntentCardProps {
  intent: MockIntent;
  onSelectWinner?: (intentId: number) => void;
  compact?: boolean;
}

export function IntentCard({ intent, onSelectWinner }: IntentCardProps) {
  const [showBids, setShowBids] = useState(false);
  const [executing, setExecuting] = useState(false);
  const [execResult, setExecResult] = useState<{ success: boolean; txId?: string; error?: string } | null>(null);

  const handleExecute = async () => {
    setExecuting(true);
    setExecResult(null);
    try {
      const txId = await fcl.mutate({
        cadence: EXECUTE_INTENT_V04_TX,
        args: (arg: typeof fcl.arg, t: typeof fcl.t) => [
          arg(intent.id.toString(), t.UInt64),
        ],
        limit: 9999,
      });
      await fcl.tx(txId).onceSealed();
      setExecResult({ success: true, txId: txId as string });
    } catch (err) {
      setExecResult({ success: false, error: err instanceof Error ? err.message : "Execution failed" });
    } finally {
      setExecuting(false);
    }
  };

  const timeSince = (date: Date) => {
    const diff = Date.now() - date.getTime();
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    if (hours > 24) return `${Math.floor(hours / 24)}d ago`;
    if (hours > 0) return `${hours}h ago`;
    return `${minutes}m ago`;
  };

  return (
    <>
      <div
        className="border border-[#1a1a1a] hover:border-[#0047FF]/30 transition-all duration-200 overflow-hidden"
        style={{ background: "#0D0D0D" }}
      >
        {/* Header */}
        <div className="px-5 pt-5 pb-4 border-b border-[#1a1a1a]">
          <div className="flex items-start justify-between">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <span
                  className="text-xs text-[#666660]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  #{intent.id}
                </span>
                <span
                  className="text-[10px] text-[#666660] border border-[#1a1a1a] px-1.5 py-0.5"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  {intent.type}
                </span>
              </div>
              <div className="flex items-center gap-1.5 text-[#666660]">
                <Clock className="w-3 h-3" />
                <span
                  className="text-[10px]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  {timeSince(intent.createdAt)}
                </span>
              </div>
            </div>
            <StatusBadge status={intent.status} />
          </div>
        </div>

        {/* Details */}
        <div className="px-5 py-4 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs text-[#666660]">Amount</span>
            <span
              className="text-sm font-bold text-[#F5F5F0]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {formatAmount(intent.amount)} FLOW
            </span>
          </div>

          {intent.type === "YIELD" && intent.targetAPY && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-[#666660]">Target APY</span>
              <span
                className="text-sm font-bold text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {intent.targetAPY}%
              </span>
            </div>
          )}

          {intent.type === "SWAP" && intent.outputToken && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-[#666660]">Output</span>
              <span
                className="text-sm font-bold text-[#F5F5F0]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                → {intent.outputToken}
              </span>
            </div>
          )}

          {intent.winningOffer != null && intent.winningOffer > 0 && (
            <div className="flex items-center justify-between">
              <span className="text-xs text-[#666660]">Solver Offers</span>
              <span
                className="text-sm font-bold text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {formatAmount(intent.winningOffer)} {intent.outputToken ?? ""}
              </span>
            </div>
          )}

          <div className="flex items-center justify-between">
            <span className="text-xs text-[#666660]">Duration</span>
            <span
              className="text-xs text-[#F5F5F0]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {intent.durationDays}d
            </span>
          </div>
        </div>

        {/* Bids + Actions */}
        <div className="px-5 pb-5">
          {intent.status === "Open" && (
            <div className="mb-3">
              <button
                onClick={() => setShowBids(true)}
                className="w-full flex items-center justify-between px-3 py-2 border border-[#1a1a1a] hover:border-[#0047FF]/40 transition-colors"
                style={{ background: "#080808" }}
              >
                <span
                  className="text-[10px] text-[#666660]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  View Bids
                </span>
                <span
                  className="text-[10px] text-[#0047FF]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  Review →
                </span>
              </button>
            </div>
          )}

          {intent.status === "BidSelected" && (
            <div className="space-y-2 mb-3">
              <div
                className="flex items-center gap-2 px-3 py-2 border border-[#F5C542]/20"
                style={{ background: "rgba(245,197,66,0.04)" }}
              >
                <span className="w-1.5 h-1.5 rounded-full bg-[#F5C542] animate-pulse shrink-0" />
                <span
                  className="text-[10px] text-[#F5C542]"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  Winner selected · ready to execute
                </span>
              </div>
              <Button
                variant="primary"
                size="sm"
                className="w-full font-mono tracking-wide text-xs"
                onClick={handleExecute}
                loading={executing}
                disabled={executing}
              >
                {executing ? "EXECUTING..." : "EXECUTE SWAP →"}
              </Button>
              {execResult && (
                <div className={`text-[10px] px-2 py-1 border ${execResult.success ? "border-[#00C566]/30 text-[#00C566]" : "border-red-800 text-red-400"}`}
                  style={{ fontFamily: "'Space Mono', monospace" }}>
                  {execResult.success ? `Executed! TX: ${execResult.txId?.slice(0, 16)}…` : execResult.error}
                </div>
              )}
            </div>
          )}

          {intent.status === "Completed" && (
            <div
              className="flex items-center gap-2 px-3 py-2 border border-[#00C566]/20"
              style={{ background: "rgba(0,197,102,0.04)" }}
            >
              <span className="w-1.5 h-1.5 rounded-full bg-[#00C566] shrink-0" />
              <span
                className="text-[10px] text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Intent completed
              </span>
            </div>
          )}
        </div>
      </div>

      <BidComparisonModal
        open={showBids}
        onClose={() => setShowBids(false)}
        intent={intent}
        onSelectWinner={onSelectWinner}
      />
    </>
  );
}
