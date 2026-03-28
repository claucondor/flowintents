import React from "react";
import { cn, type IntentStatus, STATUS_COLORS } from "@/lib/utils";

interface BadgeProps {
  status: IntentStatus;
  className?: string;
}

export function StatusBadge({ status, className }: BadgeProps) {
  const dotColor: Record<IntentStatus, string> = {
    Open: "bg-[#0047FF] animate-pulse",
    BidSelected: "bg-[#F5F5F0]",
    Active: "bg-[#00C566] animate-pulse",
    Completed: "bg-[#00C566]",
    Cancelled: "bg-red-500",
  };

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium border",
        STATUS_COLORS[status],
        className
      )}
      style={{ fontFamily: "'Space Mono', monospace" }}
    >
      <span className={cn("w-1.5 h-1.5 rounded-full", dotColor[status])} />
      {status}
    </span>
  );
}

interface GenericBadgeProps {
  children: React.ReactNode;
  variant?: "default" | "blue" | "green" | "yellow" | "red";
  className?: string;
}

export function Badge({ children, variant = "default", className }: GenericBadgeProps) {
  const variants: Record<string, string> = {
    default: "text-[#666660] bg-transparent border-[#1a1a1a]",
    blue: "text-[#0047FF] bg-[#0047FF]/10 border-[#0047FF]/30",
    green: "text-[#00C566] bg-[#00C566]/10 border-[#00C566]/30",
    yellow: "text-yellow-400 bg-yellow-400/10 border-yellow-400/30",
    red: "text-red-400 bg-red-400/10 border-red-400/30",
  };

  return (
    <span
      className={cn(
        "inline-flex items-center px-2 py-0.5 text-xs font-medium border",
        variants[variant],
        className
      )}
      style={{ fontFamily: "'Space Mono', monospace" }}
    >
      {children}
    </span>
  );
}
