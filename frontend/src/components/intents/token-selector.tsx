"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronDown, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { TOKENS } from "@/config/constants";

type TokenKey = keyof typeof TOKENS;

interface TokenSelectorProps {
  value: TokenKey;
  onChange: (token: TokenKey) => void;
  exclude?: TokenKey[];
  label?: string;
}

export function TokenSelector({ value, onChange, exclude = [], label }: TokenSelectorProps) {
  const [open, setOpen] = useState(false);

  const availableTokens = (Object.keys(TOKENS) as TokenKey[]).filter(
    (t) => !exclude.includes(t)
  );

  const selected = TOKENS[value];

  return (
    <div className="relative">
      {label && (
        <label
          className="block text-[10px] text-[#666660] mb-2 uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          {label}
        </label>
      )}
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-3 py-3 border border-[#1a1a1a] hover:border-[#0047FF]/40 transition-all duration-150 min-w-[130px]"
        style={{ background: "#0D0D0D", fontFamily: "'Space Mono', monospace" }}
      >
        <span className="text-base">{selected.emoji}</span>
        <span className="text-sm text-[#F5F5F0]">{selected.symbol}</span>
        <ChevronDown
          className={cn(
            "w-3.5 h-3.5 text-[#666660] ml-auto transition-transform",
            open && "rotate-180"
          )}
        />
      </button>

      <AnimatePresence>
        {open && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
            <motion.div
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 4 }}
              transition={{ duration: 0.12 }}
              className="absolute left-0 top-full mt-1 w-48 border border-[#1a1a1a] z-50 overflow-hidden"
              style={{ background: "#0D0D0D" }}
            >
              {availableTokens.map((tokenKey) => {
                const token = TOKENS[tokenKey];
                const isSelected = tokenKey === value;
                return (
                  <button
                    key={tokenKey}
                    type="button"
                    onClick={() => {
                      onChange(tokenKey);
                      setOpen(false);
                    }}
                    className={cn(
                      "w-full flex items-center gap-3 px-4 py-3 hover:bg-[#0047FF]/5 transition-colors text-left border-b border-[#1a1a1a] last:border-b-0",
                      isSelected && "bg-[#0047FF]/5"
                    )}
                  >
                    <span className="text-base">{token.emoji}</span>
                    <div>
                      <div
                        className="text-xs font-medium text-[#F5F5F0]"
                        style={{ fontFamily: "'Space Mono', monospace" }}
                      >
                        {token.symbol}
                      </div>
                      <div className="text-[10px] text-[#666660]">{token.name}</div>
                    </div>
                    {isSelected && <Check className="w-3.5 h-3.5 text-[#0047FF] ml-auto" />}
                  </button>
                );
              })}
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
