"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Info, AlertTriangle, CheckCircle } from "lucide-react";
import * as fcl from "@onflow/fcl";
import { Button } from "@/components/ui/button";
import { TokenSelector } from "./token-selector";
import { useWallet } from "@/lib/wallet-context";
import {
  COMMISSION_ESCROW_AMOUNT,
  DURATION_OPTIONS,
  EVM_TOKEN_ADDRESSES,
  DELIVERY_SIDE,
  DELIVERY_SIDE_LABELS,
  DeliverySideKey,
} from "@/config/constants";
import {
  CREATE_SWAP_INTENT_V04_TX,
  CREATE_YIELD_INTENT_V04_TX,
} from "@/lib/cadence";
import { getCurrentBlockHeight } from "@/lib/flow";
import { cn } from "@/lib/utils";

type IntentType = "YIELD" | "SWAP";
type TokenKey = "FLOW" | "WFLOW" | "stgUSDC";
type DurationKey = 7 | 30 | 90;
const BLOCKS_PER_DAY = 7200;

const inputClass =
  "w-full px-4 py-3 border border-[#1a1a1a] text-[#F5F5F0] text-sm placeholder:text-[#666660] focus:border-[#0047FF]/50 transition-all outline-none font-mono";

export function CreateIntentForm() {
  const { isFlowConnected, connectFlow, flowUser } = useWallet();
  const [intentType, setIntentType] = useState<IntentType>("YIELD");
  const [amount, setAmount] = useState("");
  const [outputToken, setOutputToken] = useState<TokenKey>("stgUSDC");
  const [targetAPY, setTargetAPY] = useState(8);
  const [duration, setDuration] = useState<DurationKey>(30);
  const [deliverySide, setDeliverySide] = useState<DeliverySideKey>("COA");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [commission, setCommission] = useState(COMMISSION_ESCROW_AMOUNT.toString());
  const [loading, setLoading] = useState(false);
  const [txResult, setTxResult] = useState<{ success: boolean; txId?: string; error?: string } | null>(null);

  const needsDeliveryAddress = deliverySide === "ExternalEVM" || deliverySide === "ExternalCadence";
  const escrowAmount = parseFloat(commission) || COMMISSION_ESCROW_AMOUNT;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isFlowConnected) {
      connectFlow();
      return;
    }

    setLoading(true);
    setTxResult(null);

    try {
      const amountFloat = parseFloat(amount);
      if (isNaN(amountFloat) || amountFloat <= 0) throw new Error("Invalid amount");

      // Fetch real current block height; fallback to timestamp estimate
      let currentHeight = Math.floor(Date.now() / 1000 / 2);
      try {
        currentHeight = await getCurrentBlockHeight();
      } catch {
        // use fallback
      }
      const expiryBlock = currentHeight + duration * BLOCKS_PER_DAY;

      const tokenOutAddr = intentType === "SWAP"
        ? (EVM_TOKEN_ADDRESSES[outputToken as keyof typeof EVM_TOKEN_ADDRESSES] ?? "")
        : "";
      const deliverySideValue = DELIVERY_SIDE[deliverySide];
      const deliveryAddr = needsDeliveryAddress && deliveryAddress ? deliveryAddress : null;

      if (intentType === "SWAP") {
        const txId = await fcl.mutate({
          cadence: CREATE_SWAP_INTENT_V04_TX,
          args: (arg: typeof fcl.arg, t: typeof fcl.t) => [
            arg(amountFloat.toFixed(8), t.UFix64),
            arg(tokenOutAddr, t.String),
            arg(deliverySideValue.toString(), t.UInt8),
            arg(deliveryAddr, t.Optional(t.String)),
            arg(duration.toString(), t.UInt64),
            arg(expiryBlock.toString(), t.UInt64),
            arg(escrowAmount.toFixed(8), t.UFix64),
          ],
          limit: 1000,
        });
        setTxResult({ success: true, txId });
      } else {
        const txId = await fcl.mutate({
          cadence: CREATE_YIELD_INTENT_V04_TX,
          args: (arg: typeof fcl.arg, t: typeof fcl.t) => [
            arg(amountFloat.toFixed(8), t.UFix64),
            arg(targetAPY.toFixed(8), t.UFix64),
            arg(deliverySideValue.toString(), t.UInt8),
            arg(deliveryAddr, t.Optional(t.String)),
            arg(duration.toString(), t.UInt64),
            arg(expiryBlock.toString(), t.UInt64),
            arg(escrowAmount.toFixed(8), t.UFix64),
          ],
          limit: 1000,
        });
        setTxResult({ success: true, txId });
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Transaction failed";
      setTxResult({ success: false, error: message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">

      {/* Active wallet indicator */}
      <div
        className="flex items-center justify-between px-3 py-2 border border-[#1a1a1a]"
        style={{ background: "#080808" }}
      >
        <div className="flex items-center gap-2">
          <span
            className="w-1.5 h-1.5 rounded-full shrink-0"
            style={{ background: isFlowConnected ? "#00C566" : "#333330" }}
          />
          <span
            className="text-[10px] text-[#666660] uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Cadence wallet
          </span>
        </div>
        {isFlowConnected && flowUser.addr ? (
          <span
            className="text-[10px] text-[#F5F5F0]"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {flowUser.addr.slice(0, 6)}…{flowUser.addr.slice(-4)}
          </span>
        ) : (
          <button
            type="button"
            onClick={connectFlow}
            className="text-[10px] text-[#0047FF] hover:text-[#0039CC] font-mono transition-colors"
          >
            Connect →
          </button>
        )}
      </div>

      {/* Intent Type Toggle */}
      <div>
        <label
          className="block text-[10px] text-[#666660] mb-3 uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Intent Type
        </label>
        <div className="flex gap-0 border border-[#1a1a1a]">
          {(["YIELD", "SWAP"] as const).map((type) => (
            <button
              key={type}
              type="button"
              onClick={() => setIntentType(type)}
              className={cn(
                "flex-1 py-2.5 px-4 text-xs font-medium transition-all duration-150",
                intentType === type
                  ? type === "YIELD"
                    ? "bg-[#00C566]/10 text-[#00C566] border-b-2 border-[#00C566]"
                    : "bg-[#0047FF]/10 text-[#0047FF] border-b-2 border-[#0047FF]"
                  : "text-[#666660] hover:text-[#F5F5F0] bg-transparent"
              )}
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {type}
            </button>
          ))}
        </div>
      </div>

      {/* Amount Input */}
      <div>
        <label
          className="block text-[10px] text-[#666660] mb-2 uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Amount
        </label>
        <div className="relative flex items-stretch border border-[#1a1a1a] hover:border-[#0047FF]/40 focus-within:border-[#0047FF]/50 transition-colors">
          <div
            className="flex items-center gap-2 px-3 border-r border-[#1a1a1a] shrink-0"
            style={{ background: "#0D0D0D" }}
          >
            <span
              className="text-xs text-[#666660]"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              FLOW
            </span>
          </div>
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            min="0"
            step="0.01"
            required
            className="flex-1 px-4 py-3 bg-transparent text-[#F5F5F0] text-sm font-mono placeholder:text-[#666660] outline-none"
          />
          <button
            type="button"
            className="px-3 text-[10px] text-[#0047FF] hover:text-[#0039CC] font-mono transition-colors border-l border-[#1a1a1a]"
          >
            MAX
          </button>
        </div>
      </div>

      {/* Type-specific options */}
      <AnimatePresence mode="wait">
        {intentType === "SWAP" ? (
          <motion.div
            key="swap"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.15 }}
            className="space-y-4"
          >
            <TokenSelector
              value={outputToken}
              onChange={(t) => setOutputToken(t as TokenKey)}
              exclude={["FLOW"]}
              label="Output Token"
            />
          </motion.div>
        ) : (
          <motion.div
            key="yield"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.15 }}
          >
            <div className="flex items-center justify-between mb-2">
              <label
                className="block text-[10px] text-[#666660] uppercase tracking-widest"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Target APY
              </label>
              <span
                className="text-sm font-bold text-[#00C566]"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {targetAPY}%
              </span>
            </div>
            <input
              type="range"
              min="1"
              max="20"
              step="0.5"
              value={targetAPY}
              onChange={(e) => setTargetAPY(parseFloat(e.target.value))}
              className="w-full cursor-pointer"
            />
            <div
              className="flex justify-between text-[10px] text-[#666660] mt-1"
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              <span>1%</span>
              <span>10%</span>
              <span>20%</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Duration */}
      <div>
        <label
          className="block text-[10px] text-[#666660] mb-3 uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Duration
        </label>
        <div className="flex gap-0 border border-[#1a1a1a]">
          {DURATION_OPTIONS.map((opt) => (
            <button
              key={opt.days}
              type="button"
              onClick={() => setDuration(opt.days as DurationKey)}
              className={cn(
                "flex-1 py-2.5 text-xs font-medium border-r last:border-r-0 border-[#1a1a1a] transition-all",
                duration === opt.days
                  ? "bg-[#0047FF]/10 text-[#0047FF]"
                  : "text-[#666660] hover:text-[#F5F5F0] bg-transparent"
              )}
              style={{ fontFamily: "'Space Mono', monospace" }}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* Delivery Side Selector */}
      <div>
          <label
            className="block text-[10px] text-[#666660] mb-3 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            Delivery Destination
          </label>
          <div className="grid grid-cols-2 gap-0 border border-[#1a1a1a]">
            {(Object.keys(DELIVERY_SIDE) as DeliverySideKey[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setDeliverySide(key);
                  if (key !== "ExternalEVM" && key !== "ExternalCadence") {
                    setDeliveryAddress("");
                  }
                }}
                className={cn(
                  "py-2.5 px-3 text-[11px] font-medium border-r border-b border-[#1a1a1a] last:border-r-0 transition-all",
                  deliverySide === key
                    ? "bg-[#0047FF]/10 text-[#0047FF]"
                    : "text-[#666660] hover:text-[#F5F5F0] bg-transparent"
                )}
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                {DELIVERY_SIDE_LABELS[key]}
              </button>
            ))}
          </div>
        </div>

      {/* Yield + CadenceVault warning */}
      {intentType === "YIELD" && deliverySide === "CadenceVault" && (
        <div
          className="flex items-start gap-3 p-3 border border-[#F5C542]/20 text-[11px] text-[#F5C542]"
          style={{ background: "rgba(245,197,66,0.04)", fontFamily: "'Space Mono', monospace" }}
        >
          <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
          <span>
            Yield share tokens (e.g. aFLOWEVMb) may not be bridgeable to Cadence.
            If bridging fails, tokens will remain in your COA (EVM).
            Consider selecting &quot;My COA&quot; for yield intents.
          </span>
        </div>
      )}

      {/* Delivery Address (for external destinations) */}
      {needsDeliveryAddress && (
        <div>
          <label
            className="block text-[10px] text-[#666660] mb-2 uppercase tracking-widest"
            style={{ fontFamily: "'Space Mono', monospace" }}
          >
            {deliverySide === "ExternalEVM" ? "EVM Address" : "Cadence Address"}
          </label>
          <input
            type="text"
            value={deliveryAddress}
            onChange={(e) => setDeliveryAddress(e.target.value)}
            placeholder={deliverySide === "ExternalEVM" ? "0x..." : "0x..."}
            required
            className={inputClass}
          />
        </div>
      )}

      {/* Commission Escrow */}
      <div>
        <label
          className="block text-[10px] text-[#666660] mb-2 uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          Solver Commission (FLOW)
        </label>
        <div className="relative flex items-stretch border border-[#1a1a1a] hover:border-[#0047FF]/40 focus-within:border-[#0047FF]/50 transition-colors">
          <div
            className="flex items-center gap-2 px-3 border-r border-[#1a1a1a] shrink-0"
            style={{ background: "#0D0D0D" }}
          >
            <span className="text-xs text-[#666660]" style={{ fontFamily: "'Space Mono', monospace" }}>FLOW</span>
          </div>
          <input
            type="number"
            value={commission}
            onChange={(e) => setCommission(e.target.value)}
            placeholder="0.01"
            min="0.001"
            step="0.001"
            required
            className="flex-1 px-4 py-3 bg-transparent text-[#F5F5F0] text-sm font-mono placeholder:text-[#666660] outline-none"
          />
        </div>
        <p className="text-[10px] text-[#666660] mt-1" style={{ fontFamily: "'Space Mono', monospace" }}>
          Higher commission attracts more solvers. Locked until execution or cancel.
        </p>
      </div>

      {/* Total cost */}
      {amount && !isNaN(parseFloat(amount)) && (
        <div className="border border-[#1a1a1a] divide-y divide-[#1a1a1a]">
          <div className="flex justify-between px-4 py-3 text-xs">
            <span className="text-[#666660]" style={{ fontFamily: "'Space Mono', monospace" }}>
              Principal (declared)
            </span>
            <span className="text-[#F5F5F0]" style={{ fontFamily: "'Space Mono', monospace" }}>
              {parseFloat(amount).toFixed(4)} FLOW
              <span className="text-[#666660] ml-1">(stays in wallet)</span>
            </span>
          </div>
          <div className="flex justify-between px-4 py-3 text-xs">
            <span className="text-[#666660]" style={{ fontFamily: "'Space Mono', monospace" }}>
              Commission Escrow
            </span>
            <span className="text-[#F5F5F0]" style={{ fontFamily: "'Space Mono', monospace" }}>{escrowAmount} FLOW</span>
          </div>
          <div className="flex justify-between px-4 py-3 text-xs">
            <span className="text-[#F5F5F0] font-bold" style={{ fontFamily: "'Space Mono', monospace" }}>
              Locked Now
            </span>
            <span className="text-[#0047FF] font-bold" style={{ fontFamily: "'Space Mono', monospace" }}>
              {escrowAmount.toFixed(4)} FLOW
            </span>
          </div>
        </div>
      )}

      {/* Result */}
      <AnimatePresence>
        {txResult && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className={cn(
              "flex items-start gap-3 p-4 border text-xs",
              txResult.success
                ? "border-[#00C566]/30 text-[#00C566]"
                : "border-red-800 text-red-400"
            )}
            style={{ background: txResult.success ? "#00C56608" : "#ff000008" }}
          >
            {txResult.success ? (
              <CheckCircle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            ) : (
              <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            )}
            <div style={{ fontFamily: "'Space Mono', monospace" }}>
              {txResult.success ? (
                <>
                  <div className="font-medium">Intent created successfully</div>
                  <div className="text-[#00C566]/70 text-[11px] mt-1.5">
                    Solvers are now competing to fill your intent. Check the{" "}
                    <a href="/live" className="underline hover:text-[#00C566]">Live Feed</a>{" "}
                    or{" "}
                    <a href="/app" className="underline hover:text-[#00C566]">My Intents</a>{" "}
                    to see bids as they arrive.
                  </div>
                  <div className="text-[#00C566]/40 text-[10px] mt-1 break-all">
                    TX: {txResult.txId}
                  </div>
                </>
              ) : (
                <>
                  <div className="font-medium">Transaction failed</div>
                  <div className="text-red-400/60 text-[10px] mt-1">{txResult.error}</div>
                </>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Submit */}
      <Button
        type="submit"
        variant="primary"
        size="lg"
        className="w-full font-mono tracking-wide text-xs"
        loading={loading}
        disabled={!amount || loading}
      >
        {!isFlowConnected
          ? "CONNECT FLOW WALLET TO CONTINUE"
          : loading
          ? "CREATING..."
          : `CREATE ${intentType} INTENT →`}
      </Button>
    </form>
  );
}
