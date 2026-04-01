"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronDown, LogOut, Copy, Check, Zap } from "lucide-react";
import { useWallet } from "@/lib/wallet-context";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortenAddress } from "@/lib/utils";
import { Button } from "@/components/ui/button";

export function WalletButton() {
  const { flowUser, connectFlow, disconnectFlow, isFlowConnected } = useWallet();
  const { address: evmAddress, isConnected: isEvmConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect: disconnectEvm } = useDisconnect();
  const [showDropdown, setShowDropdown] = useState(false);
  const [copiedFlow, setCopiedFlow] = useState(false);
  const [copiedEvm, setCopiedEvm] = useState(false);
  const [mounted, setMounted] = useState(false);

  React.useEffect(() => { setMounted(true); }, []);

  if (!mounted) return null;

  const isAnyConnected = isFlowConnected || isEvmConnected;

  const copyAddress = (address: string, type: "flow" | "evm") => {
    navigator.clipboard.writeText(address);
    if (type === "flow") {
      setCopiedFlow(true);
      setTimeout(() => setCopiedFlow(false), 2000);
    } else {
      setCopiedEvm(true);
      setTimeout(() => setCopiedEvm(false), 2000);
    }
  };

  if (!isAnyConnected) {
    return (
      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={connectFlow}
          className="gap-2 font-mono tracking-wide"
        >
          FLOW
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => {
            const injector = connectors.find((c) => c.id === "injected");
            if (injector) connect({ connector: injector });
          }}
          className="gap-2"
        >
          <Zap className="w-3.5 h-3.5" />
          <span className="hidden sm:inline text-xs font-mono tracking-wide">EVM</span>
        </Button>
      </div>
    );
  }

  return (
    <div className="relative">
      <button
        onClick={() => setShowDropdown(!showDropdown)}
        className="flex items-center gap-2 px-3 py-2 border border-[var(--border)] hover:border-[#0047FF]/40 transition-all duration-200 text-sm"
        style={{ background: "var(--bg-card)", color: "var(--text-primary)", fontFamily: "'Space Mono', monospace" }}
      >
        <span className="text-xs">
          {isFlowConnected
            ? shortenAddress(flowUser.addr || "")
            : isEvmConnected
            ? shortenAddress(evmAddress || "")
            : "—"}
        </span>
        <span className="text-[9px] border border-[var(--border)] px-1.5 py-0.5 hidden sm:inline" style={{ color: "var(--text-muted)" }}>
          FLOW MAINNET
        </span>
        <ChevronDown
          className={`w-3 h-3 transition-transform ${showDropdown ? "rotate-180" : ""}`}
          style={{ color: "var(--text-muted)" }}
        />
      </button>

      <AnimatePresence>
        {showDropdown && (
          <>
            <div
              className="fixed inset-0 z-40"
              onClick={() => setShowDropdown(false)}
            />
            <motion.div
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 6 }}
              transition={{ duration: 0.12 }}
              className="absolute right-0 top-full mt-1 w-72 border border-[var(--border)] z-50 overflow-hidden"
              style={{ background: "var(--bg-card)" }}
            >
              {isFlowConnected && (
                <div className="p-4 border-b border-[var(--border)]">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-[10px] font-medium text-[var(--text-muted)] uppercase tracking-widest" style={{ fontFamily: "'Space Mono', monospace" }}>
                      Flow / Cadence
                    </span>
                    <span className="ml-auto w-1.5 h-1.5 bg-[#00C566] rounded-full animate-pulse" />
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm" style={{ color: "var(--text-primary)", fontFamily: "'Space Mono', monospace" }}>
                      {shortenAddress(flowUser.addr || "", 6)}
                    </span>
                    <button
                      onClick={() => copyAddress(flowUser.addr || "", "flow")}
                      className="p-1.5 hover:bg-[var(--border)] text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
                    >
                      {copiedFlow ? (
                        <Check className="w-3.5 h-3.5 text-[#00C566]" />
                      ) : (
                        <Copy className="w-3.5 h-3.5" />
                      )}
                    </button>
                  </div>
                </div>
              )}

              {isEvmConnected && (
                <div className="p-4 border-b border-[var(--border)]">
                  <div className="flex items-center gap-2 mb-2">
                    <Zap className="w-3 h-3 text-[#0047FF]" />
                    <span className="text-[10px] font-medium text-[var(--text-muted)] uppercase tracking-widest" style={{ fontFamily: "'Space Mono', monospace" }}>
                      Flow EVM
                    </span>
                    <span className="ml-auto w-1.5 h-1.5 bg-[#00C566] rounded-full animate-pulse" />
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm" style={{ color: "var(--text-primary)", fontFamily: "'Space Mono', monospace" }}>
                      {shortenAddress(evmAddress || "", 6)}
                    </span>
                    <button
                      onClick={() => copyAddress(evmAddress || "", "evm")}
                      className="p-1.5 hover:bg-[var(--border)] text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
                    >
                      {copiedEvm ? (
                        <Check className="w-3.5 h-3.5 text-[#00C566]" />
                      ) : (
                        <Copy className="w-3.5 h-3.5" />
                      )}
                    </button>
                  </div>
                </div>
              )}

              {!isFlowConnected && (
                <button
                  onClick={() => { connectFlow(); setShowDropdown(false); }}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-[#0047FF]/5 transition-colors text-left"
                >
                  <span className="text-sm text-[var(--text-muted)] hover:text-[var(--text-primary)] font-mono">Connect Flow Wallet</span>
                </button>
              )}

              {!isEvmConnected && (
                <button
                  onClick={() => {
                    const injector = connectors.find((c) => c.id === "injected");
                    if (injector) connect({ connector: injector });
                    setShowDropdown(false);
                  }}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-[#0047FF]/5 transition-colors text-left"
                >
                  <Zap className="w-4 h-4 text-[#0047FF]" />
                  <span className="text-sm text-[var(--text-muted)] hover:text-[var(--text-primary)] font-mono">Connect EVM Wallet</span>
                </button>
              )}

              <div className="p-2 border-t border-[var(--border)]">
                <button
                  onClick={() => {
                    if (isFlowConnected) disconnectFlow();
                    if (isEvmConnected) disconnectEvm();
                    setShowDropdown(false);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-2 hover:bg-red-950 text-red-500 hover:text-red-400 transition-colors text-xs font-mono"
                >
                  <LogOut className="w-3.5 h-3.5" />
                  Disconnect All
                </button>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
