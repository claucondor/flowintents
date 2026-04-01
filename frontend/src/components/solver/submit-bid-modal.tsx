"use client";

import React, { useState } from "react";
import * as fcl from "@onflow/fcl";
import { Info, AlertTriangle, CheckCircle } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { SUBMIT_BID_TX } from "@/lib/cadence";
import { type MockIntent, formatAmount } from "@/lib/utils";
import { cn } from "@/lib/utils";

interface SubmitBidModalProps {
  open: boolean;
  onClose: () => void;
  intent: MockIntent;
  isConnected: boolean;
  onConnectFlow: () => void;
}

const STRATEGIES = [
  { value: "PunchSwap/FLOW-USDC", label: "PunchSwap FLOW/USDC" },
  { value: "Ankr/liquid-stake", label: "Ankr Liquid Staking" },
  { value: "MORE/wflow-vault", label: "MORE Finance WFLOW Vault" },
  { value: "WFLOW/wrap", label: "WFLOW Wrap (1:1)" },
  { value: "custom", label: "Custom Strategy" },
];

const inputClass =
  "w-full px-4 py-3 border border-[var(--border)] bg-transparent text-[var(--text-primary)] text-xs placeholder:text-[var(--text-muted)] focus:border-[#0047FF]/50 transition-all outline-none";

export function SubmitBidModal({
  open,
  onClose,
  intent,
  isConnected,
  onConnectFlow,
}: SubmitBidModalProps) {
  const [offeredValue, setOfferedValue] = useState("");
  const [gasBid, setGasBid] = useState("0.01");
  const [strategy, setStrategy] = useState(STRATEGIES[0].value);
  const [customStrategy, setCustomStrategy] = useState("");
  const [targetChain, setTargetChain] = useState<"cadence" | "evm">("cadence");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ success: boolean; txId?: string; error?: string } | null>(null);

  const strategyString = strategy === "custom" ? customStrategy : strategy;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isConnected) {
      onConnectFlow();
      return;
    }

    setLoading(true);
    setResult(null);

    try {
      const offeredFloat = parseFloat(offeredValue);
      const gasBidFloat = parseFloat(gasBid);

      if (isNaN(offeredFloat) || offeredFloat <= 0) throw new Error("Invalid offered value");
      if (isNaN(gasBidFloat) || gasBidFloat <= 0) throw new Error("Invalid gas bid");
      if (!strategyString.trim()) throw new Error("Strategy description is required");

      const txId = await fcl.mutate({
        cadence: SUBMIT_BID_TX,
        args: (arg: typeof fcl.arg, t: typeof fcl.t) => [
          arg(intent.id.toString(), t.UInt64),
          intent.type === "YIELD"
            ? arg(offeredFloat.toFixed(8), t.Optional(t.UFix64))
            : arg(null, t.Optional(t.UFix64)),
          intent.type === "SWAP"
            ? arg(offeredFloat.toFixed(8), t.Optional(t.UFix64))
            : arg(null, t.Optional(t.UFix64)),
          arg(null, t.Optional(t.UInt64)),
          arg(targetChain, t.Optional(t.String)),
          arg(gasBidFloat.toFixed(8), t.UFix64),
          arg(strategyString, t.String),
          arg([], t.Array(t.UInt8)),
        ],
        limit: 1000,
      });

      setResult({ success: true, txId });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Transaction failed";
      setResult({ success: false, error: message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal open={open} onClose={onClose} title={`Submit Bid · Intent #${intent.id}`}>
      {/* Intent summary */}
      <div className="mb-6 border border-[var(--border)] divide-y divide-[var(--border)]">
        <div
          className="px-4 py-2 text-[10px] text-[var(--text-muted)] uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Intent Details
        </div>
        <div className="grid grid-cols-2 gap-0 divide-x divide-y divide-[var(--border)]">
          <div className="px-4 py-3">
            <span
              className="block text-[10px] text-[var(--text-muted)] mb-0.5"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Type
            </span>
            <span
              className="text-xs"
              style={{ color: "var(--text-primary)", fontFamily: "'Space Mono', monospace" }}
            >
              {intent.type}
            </span>
          </div>
          <div className="px-4 py-3">
            <span
              className="block text-[10px] text-[var(--text-muted)] mb-0.5"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Amount
            </span>
            <span
              className="text-xs"
              style={{ color: "var(--text-primary)" }}
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {formatAmount(intent.amount)} FLOW
            </span>
          </div>
          {intent.type === "YIELD" && (
            <div className="px-4 py-3">
              <span
                className="block text-[10px] text-[var(--text-muted)] mb-0.5"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Target APY
              </span>
              <span
                className="text-xs text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {intent.targetAPY}%
              </span>
            </div>
          )}
          {intent.type === "SWAP" && (
            <div className="px-4 py-3">
              <span
                className="block text-[10px] text-[var(--text-muted)] mb-0.5"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Min Out
              </span>
              <span
                className="text-xs"
                style={{ color: "var(--text-primary)" }}
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {formatAmount(intent.minAmountOut || 0)} {intent.outputToken}
              </span>
            </div>
          )}
          <div className="px-4 py-3">
            <span
              className="block text-[10px] text-[var(--text-muted)] mb-0.5"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Duration
            </span>
            <span
              className="text-xs"
              style={{ color: "var(--text-primary)" }}
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {intent.durationDays}d
            </span>
          </div>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Offered value */}
        <div>
          <label
            className="block text-[10px] text-[var(--text-muted)] mb-2 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {intent.type === "YIELD" ? "Offered APY (%)" : `Offered Amount Out (${intent.outputToken})`}
          </label>
          <input
            type="number"
            value={offeredValue}
            onChange={(e) => setOfferedValue(e.target.value)}
            placeholder={intent.type === "YIELD" ? "e.g. 9.5" : `e.g. ${formatAmount(intent.minAmountOut || 0)}`}
            step="0.01"
            min="0"
            required
            className={inputClass}
            style={{ fontFamily: "'Space Mono', monospace" }}
          />
          {intent.type === "YIELD" && intent.targetAPY && parseFloat(offeredValue) > 0 && (
            <p
              className={cn(
                "text-[10px] mt-1",
                parseFloat(offeredValue) >= intent.targetAPY ? "text-[#00C566]" : "text-yellow-400"
              )}
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {parseFloat(offeredValue) >= intent.targetAPY
                ? `✓ Meets target (${intent.targetAPY}%)`
                : `Below target (${intent.targetAPY}%)`}
            </p>
          )}
        </div>

        {/* Strategy */}
        <div>
          <label
            className="block text-[10px] text-[var(--text-muted)] mb-2 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Strategy
          </label>
          <select
            value={strategy}
            onChange={(e) => setStrategy(e.target.value)}
            className={cn(inputClass, "cursor-pointer")}
            style={{ fontFamily: "'Space Mono', monospace", background: "var(--bg-card)" }}
          >
            {STRATEGIES.map((s) => (
              <option key={s.value} value={s.value} style={{ background: "var(--bg-card)" }}>
                {s.label}
              </option>
            ))}
          </select>
          {strategy === "custom" && (
            <textarea
              value={customStrategy}
              onChange={(e) => setCustomStrategy(e.target.value)}
              placeholder="Describe your custom execution strategy"
              rows={2}
              required
              className={cn(inputClass, "mt-2 resize-none")}
              style={{ fontFamily: "'Space Mono', monospace" }}
            />
          )}
        </div>

        {/* Target chain */}
        <div>
          <label
            className="block text-[10px] text-[var(--text-muted)] mb-2 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Execution Chain
          </label>
          <div className="flex gap-0 border border-[var(--border)]">
            {(["cadence", "evm"] as const).map((chain) => (
              <button
                key={chain}
                type="button"
                onClick={() => setTargetChain(chain)}
                className={cn(
                  "flex-1 py-2.5 text-xs font-medium border-r last:border-r-0 border-[var(--border)] transition-all capitalize",
                  targetChain === chain
                    ? "bg-[#0047FF]/10 text-[#0047FF]"
                    : "text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                )}
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {chain === "cadence" ? "Cadence" : "EVM"}
              </button>
            ))}
          </div>
        </div>

        {/* Gas bid */}
        <div>
          <label
            className="block text-[10px] text-[var(--text-muted)] mb-2 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Max Gas Bid (FLOW)
          </label>
          <input
            type="number"
            value={gasBid}
            onChange={(e) => setGasBid(e.target.value)}
            placeholder="0.01"
            step="0.001"
            min="0"
            max="0.01"
            required
            className={inputClass}
            style={{ fontFamily: "'Space Mono', monospace" }}
          />
          <div className="flex items-center gap-1.5 mt-1.5">
            <Info className="w-3 h-3 text-[var(--text-muted)]" />
            <p
              className="text-[10px] text-[var(--text-muted)]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              Max suggested: 0.01 FLOW. Lower gas bid improves your score.
            </p>
          </div>
        </div>

        {/* Result */}
        {result && (
          <div
            className={cn(
              "flex items-start gap-3 p-4 border text-xs",
              result.success
                ? "border-[#00C566]/30 text-[#00C566]"
                : "border-red-800 text-red-400"
            )}
            style={{
              background: result.success ? "var(--accent-dim)" : "#ff000008",
              fontFamily: "'Space Mono', monospace",
            }}
          >
            {result.success ? (
              <CheckCircle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            ) : (
              <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            )}
            <div>
              {result.success ? (
                <>
                  <div>Bid submitted successfully</div>
                  <div className="text-[10px] mt-1 break-all text-[#00C566]/60">
                    TX: {result.txId}
                  </div>
                </>
              ) : (
                <>
                  <div>Submission failed</div>
                  <div className="text-[10px] mt-1 text-red-400/60">{result.error}</div>
                </>
              )}
            </div>
          </div>
        )}

        <Button
          type="submit"
          variant="primary"
          size="lg"
          className="w-full font-mono tracking-wide text-xs"
          loading={loading}
        >
          {!isConnected ? "CONNECT FLOW WALLET" : "SUBMIT BID →"}
        </Button>
      </form>
    </Modal>
  );
}
