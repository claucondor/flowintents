import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function shortenAddress(address: string, chars = 4): string {
  if (!address) return "";
  if (address.startsWith("0x")) {
    return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
  }
  return `${address.slice(0, chars)}...${address.slice(-chars)}`;
}

export function formatAmount(amount: number, decimals = 6): string {
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(amount);
}

export function formatTimeRemaining(expiryTimestamp: number): string {
  const now = Date.now();
  const diff = expiryTimestamp - now;
  if (diff <= 0) return "Expired";
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  if (days > 0) return `${days}d ${hours}h`;
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
  return `${hours}h ${minutes}m`;
}

export type IntentStatus = "Open" | "BidSelected" | "Active" | "Completed" | "Cancelled";

export const STATUS_COLORS: Record<IntentStatus, string> = {
  Open: "text-[#0047FF] bg-[#0047FF]/10 border-[#0047FF]/30",
  BidSelected: "text-[var(--text-primary)] bg-[var(--border)]/30 border-[var(--border)]",
  Active: "text-[#00C566] bg-[#00C566]/10 border-[#00C566]/30",
  Completed: "text-[#00C566] bg-[#00C566]/5 border-[#00C566]/20",
  Cancelled: "text-red-400 bg-red-400/10 border-red-400/30",
};

export interface MockIntent {
  id: number;
  type: "YIELD" | "SWAP";
  amount: number;
  status: IntentStatus;
  targetAPY?: number;
  minAmountOut?: number;
  outputToken?: string;
  durationDays: number;
  createdAt: Date;
  bids: MockBid[];
  winningOffer?: number; // offeredAmountOut or offeredAPY from winning bid
}

export interface MockBid {
  id: number;
  solverAddress: string;
  offeredAPY?: number;
  offeredAmountOut?: number;
  gasBid: number;
  strategy: string;
  score: number;
  createdAt: Date;
}

export const MOCK_INTENTS: MockIntent[] = [
  {
    id: 1,
    type: "YIELD",
    amount: 500,
    status: "Open",
    targetAPY: 8.5,
    durationDays: 30,
    createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
    bids: [
      {
        id: 1,
        solverAddress: "0xabcd...1234",
        offeredAPY: 9.2,
        gasBid: 0.008,
        strategy: "Ankr staking + AAVE lending",
        score: 6.73,
        createdAt: new Date(Date.now() - 1 * 60 * 60 * 1000),
      },
      {
        id: 2,
        solverAddress: "0xef01...5678",
        offeredAPY: 10.1,
        gasBid: 0.01,
        strategy: "PunchSwap LP + yield optimization",
        score: 7.37,
        createdAt: new Date(Date.now() - 30 * 60 * 1000),
      },
    ],
  },
  {
    id: 2,
    type: "SWAP",
    amount: 1000,
    status: "BidSelected",
    minAmountOut: 950,
    outputToken: "stgUSDC",
    durationDays: 7,
    createdAt: new Date(Date.now() - 24 * 60 * 60 * 1000),
    bids: [
      {
        id: 3,
        solverAddress: "0xbcde...2345",
        offeredAmountOut: 982,
        gasBid: 0.009,
        strategy: "PunchSwap FLOW/USDC route",
        score: 687.7,
        createdAt: new Date(Date.now() - 20 * 60 * 60 * 1000),
      },
    ],
  },
  {
    id: 3,
    type: "YIELD",
    amount: 250,
    status: "Completed",
    targetAPY: 6.0,
    durationDays: 90,
    createdAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    bids: [],
  },
  {
    id: 4,
    type: "SWAP",
    amount: 2000,
    status: "Open",
    minAmountOut: 1900,
    outputToken: "WFLOW",
    durationDays: 7,
    createdAt: new Date(Date.now() - 30 * 60 * 1000),
    bids: [],
  },
  {
    id: 5,
    type: "YIELD",
    amount: 750,
    status: "Active",
    targetAPY: 12.0,
    durationDays: 30,
    createdAt: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000),
    bids: [],
  },
];

export const MOCK_ALL_INTENTS: MockIntent[] = [
  {
    id: 6,
    type: "YIELD",
    amount: 300,
    status: "Open",
    targetAPY: 7.5,
    durationDays: 30,
    createdAt: new Date(Date.now() - 1 * 60 * 60 * 1000),
    bids: [],
  },
  {
    id: 7,
    type: "SWAP",
    amount: 5000,
    status: "Open",
    minAmountOut: 4800,
    outputToken: "stgUSDC",
    durationDays: 7,
    createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
    bids: [],
  },
  {
    id: 8,
    type: "YIELD",
    amount: 1500,
    status: "Open",
    targetAPY: 15.0,
    durationDays: 90,
    createdAt: new Date(Date.now() - 3 * 60 * 60 * 1000),
    bids: [
      {
        id: 5,
        solverAddress: "0x9abc...def0",
        offeredAPY: 16.2,
        gasBid: 0.01,
        strategy: "Multi-protocol yield optimization",
        score: 11.64,
        createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
      },
    ],
  },
  ...MOCK_INTENTS.filter((i) => i.status === "Open"),
];
