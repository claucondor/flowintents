// flow.ts — all on-chain reads from Flow mainnet via REST API
// Pure fetch, no FCL browser dependency — works server-side and client-side.

const ACCESS_NODE = "https://rest-mainnet.onflow.org";
const DEPLOYER = "0xc65395858a38d8ff";

// ── CDC value parser ──────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseCDC(value: any): any {
  if (value === null || value === undefined) return null;

  const { type, value: v } = value;

  switch (type) {
    case "Optional":
      return v === null ? null : parseCDC(v);
    case "UInt8":
    case "UInt16":
    case "UInt32":
    case "UInt64":
    case "UInt128":
    case "UInt256":
    case "Int8":
    case "Int16":
    case "Int32":
    case "Int64":
    case "Int":
    case "UInt":
      return parseInt(v, 10);
    case "UFix64":
    case "Fix64":
      return parseFloat(v);
    case "Bool":
      return v === true || v === "true";
    case "String":
      return v as string;
    case "Address":
      return v as string;
    case "Array":
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (v as any[]).map(parseCDC);
    case "Dictionary":
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return Object.fromEntries((v as any[]).map((entry: any) => [parseCDC(entry.key), parseCDC(entry.value)]));
    case "Struct":
    case "Resource":
    case "Event":
    case "Contract":
    case "Enum": {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result: Record<string, any> = {};
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      for (const field of (v as any).fields ?? []) {
        result[field.name] = parseCDC(field.value);
      }
      // For enums, also expose the rawValue
      if (type === "Enum") {
        result["rawValue"] = parseCDC((v as any).fields?.[0]?.value);
      }
      return result;
    }
    case "Void":
      return null;
    default:
      return v;
  }
}

// ── Script runner ──────────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function executeScript(code: string, args: any[] = []): Promise<any> {
  const res = await fetch(`${ACCESS_NODE}/v1/scripts`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      script: Buffer.from(code).toString("base64"),
      arguments: args.map((a) =>
        Buffer.from(JSON.stringify(a)).toString("base64")
      ),
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Script failed (${res.status}): ${text}`);
  }
  const encoded = await res.text();
  // Response is a base64-encoded JSON-CDC value (string body, not JSON wrapper)
  let decoded: string;
  try {
    decoded = Buffer.from(encoded.replace(/^"|"$/g, "").replace(/\\n/g, "").trim(), "base64").toString();
  } catch {
    // Try parsing the response as JSON first (some versions wrap differently)
    decoded = Buffer.from(JSON.parse(encoded), "base64").toString();
  }
  const cdcValue = JSON.parse(decoded);
  return parseCDC(cdcValue);
}

// ── Types ─────────────────────────────────────────────────────────────────────

export interface Intent {
  id: number;
  intentOwner: string;
  principalAmount: number;
  intentType: number; // 0=Yield, 1=Swap, 2=BridgeYield
  targetAPY: number;
  minAmountOut: number | null;
  maxFeeBPS: number | null;
  durationDays: number;
  expiryBlock: number;
  status: number; // 0=Open, 1=BidSelected, 2=Active, 3=Completed, 4=Cancelled, 5=Expired
  winningBidID: number | null;
  createdAt: number;
  principalSide: number; // 0=cadence, 1=evm
  gasEscrowBalance: number;
  executionDeadlineBlock: number;
}

export interface Bid {
  id: number;
  intentID: number;
  solverAddress: string;
  solverEVMAddress: string;
  offeredAPY: number | null;
  offeredAmountOut: number | null;
  estimatedFeeBPS: number | null;
  targetChain: string | null;
  maxGasBid: number;
  strategy: string;
  submittedAt: number;
  score: number;
}

// ── Cadence scripts ───────────────────────────────────────────────────────────

const GET_TOTAL_INTENTS_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}
access(all) fun main(): UInt64 {
  return IntentMarketplaceV0_3.totalIntents
}
`;

const GET_OPEN_INTENTS_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}
access(all) fun main(): [UInt64] {
  return IntentMarketplaceV0_3.getOpenIntents()
}
`;

const GET_INTENT_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}
access(all) fun main(intentID: UInt64): IntentMarketplaceV0_3.IntentStatus? {
  return IntentMarketplaceV0_3.getIntentStatus(id: intentID)
}
`;

// Script to get intent fields we need — returns a struct
const GET_INTENT_FULL_SCRIPT = `
import IntentMarketplaceV0_3 from ${DEPLOYER}

access(all) struct IntentData {
  access(all) let id: UInt64
  access(all) let intentOwner: Address
  access(all) let principalAmount: UFix64
  access(all) let intentType: UInt8
  access(all) let targetAPY: UFix64
  access(all) let minAmountOut: UFix64?
  access(all) let maxFeeBPS: UInt64?
  access(all) let durationDays: UInt64
  access(all) let expiryBlock: UInt64
  access(all) let status: UInt8
  access(all) let winningBidID: UInt64?
  access(all) let createdAt: UFix64
  access(all) let principalSide: UInt8
  access(all) let gasEscrowBalance: UFix64
  access(all) let executionDeadlineBlock: UInt64

  init(
    id: UInt64,
    intentOwner: Address,
    principalAmount: UFix64,
    intentType: UInt8,
    targetAPY: UFix64,
    minAmountOut: UFix64?,
    maxFeeBPS: UInt64?,
    durationDays: UInt64,
    expiryBlock: UInt64,
    status: UInt8,
    winningBidID: UInt64?,
    createdAt: UFix64,
    principalSide: UInt8,
    gasEscrowBalance: UFix64,
    executionDeadlineBlock: UInt64
  ) {
    self.id = id
    self.intentOwner = intentOwner
    self.principalAmount = principalAmount
    self.intentType = intentType
    self.targetAPY = targetAPY
    self.minAmountOut = minAmountOut
    self.maxFeeBPS = maxFeeBPS
    self.durationDays = durationDays
    self.expiryBlock = expiryBlock
    self.status = status
    self.winningBidID = winningBidID
    self.createdAt = createdAt
    self.principalSide = principalSide
    self.gasEscrowBalance = gasEscrowBalance
    self.executionDeadlineBlock = executionDeadlineBlock
  }
}

access(all) fun main(intentID: UInt64): IntentData? {
  if let intent = IntentMarketplaceV0_3.getIntent(id: intentID) {
    return IntentData(
      id: intent.id,
      intentOwner: intent.intentOwner,
      principalAmount: intent.principalAmount,
      intentType: intent.intentType.rawValue,
      targetAPY: intent.targetAPY,
      minAmountOut: intent.minAmountOut,
      maxFeeBPS: intent.maxFeeBPS,
      durationDays: intent.durationDays,
      expiryBlock: intent.expiryBlock,
      status: intent.status.rawValue,
      winningBidID: intent.winningBidID,
      createdAt: intent.createdAt,
      principalSide: intent.principalSide.rawValue,
      gasEscrowBalance: intent.getGasEscrowBalance(),
      executionDeadlineBlock: intent.executionDeadlineBlock
    )
  }
  return nil
}
`;

const GET_BIDS_FOR_INTENT_SCRIPT = `
import BidManagerV0_3 from ${DEPLOYER}
access(all) fun main(intentID: UInt64): [UInt64] {
  return BidManagerV0_3.getBidsForIntent(intentID: intentID)
}
`;

const GET_BID_SCRIPT = `
import BidManagerV0_3 from ${DEPLOYER}

access(all) struct BidData {
  access(all) let id: UInt64
  access(all) let intentID: UInt64
  access(all) let solverAddress: Address
  access(all) let solverEVMAddress: String
  access(all) let offeredAPY: UFix64?
  access(all) let offeredAmountOut: UFix64?
  access(all) let estimatedFeeBPS: UInt64?
  access(all) let targetChain: String?
  access(all) let maxGasBid: UFix64
  access(all) let strategy: String
  access(all) let submittedAt: UFix64
  access(all) let score: UFix64

  init(
    id: UInt64,
    intentID: UInt64,
    solverAddress: Address,
    solverEVMAddress: String,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?,
    targetChain: String?,
    maxGasBid: UFix64,
    strategy: String,
    submittedAt: UFix64,
    score: UFix64
  ) {
    self.id = id
    self.intentID = intentID
    self.solverAddress = solverAddress
    self.solverEVMAddress = solverEVMAddress
    self.offeredAPY = offeredAPY
    self.offeredAmountOut = offeredAmountOut
    self.estimatedFeeBPS = estimatedFeeBPS
    self.targetChain = targetChain
    self.maxGasBid = maxGasBid
    self.strategy = strategy
    self.submittedAt = submittedAt
    self.score = score
  }
}

access(all) fun main(bidID: UInt64): BidData? {
  if let bid = BidManagerV0_3.getBid(bidID: bidID) {
    return BidData(
      id: bid.id,
      intentID: bid.intentID,
      solverAddress: bid.solverAddress,
      solverEVMAddress: bid.solverEVMAddress,
      offeredAPY: bid.offeredAPY,
      offeredAmountOut: bid.offeredAmountOut,
      estimatedFeeBPS: bid.estimatedFeeBPS,
      targetChain: bid.targetChain,
      maxGasBid: bid.maxGasBid,
      strategy: bid.strategy,
      submittedAt: bid.submittedAt,
      score: bid.score
    )
  }
  return nil
}
`;

const GET_WINNING_BID_SCRIPT = `
import BidManagerV0_3 from ${DEPLOYER}

access(all) struct BidData {
  access(all) let id: UInt64
  access(all) let intentID: UInt64
  access(all) let solverAddress: Address
  access(all) let solverEVMAddress: String
  access(all) let offeredAPY: UFix64?
  access(all) let offeredAmountOut: UFix64?
  access(all) let estimatedFeeBPS: UInt64?
  access(all) let targetChain: String?
  access(all) let maxGasBid: UFix64
  access(all) let strategy: String
  access(all) let submittedAt: UFix64
  access(all) let score: UFix64

  init(
    id: UInt64,
    intentID: UInt64,
    solverAddress: Address,
    solverEVMAddress: String,
    offeredAPY: UFix64?,
    offeredAmountOut: UFix64?,
    estimatedFeeBPS: UInt64?,
    targetChain: String?,
    maxGasBid: UFix64,
    strategy: String,
    submittedAt: UFix64,
    score: UFix64
  ) {
    self.id = id
    self.intentID = intentID
    self.solverAddress = solverAddress
    self.solverEVMAddress = solverEVMAddress
    self.offeredAPY = offeredAPY
    self.offeredAmountOut = offeredAmountOut
    self.estimatedFeeBPS = estimatedFeeBPS
    self.targetChain = targetChain
    self.maxGasBid = maxGasBid
    self.strategy = strategy
    self.submittedAt = submittedAt
    self.score = score
  }
}

access(all) fun main(intentID: UInt64): BidData? {
  if let bid = BidManagerV0_3.getWinningBid(intentID: intentID) {
    return BidData(
      id: bid.id,
      intentID: bid.intentID,
      solverAddress: bid.solverAddress,
      solverEVMAddress: bid.solverEVMAddress,
      offeredAPY: bid.offeredAPY,
      offeredAmountOut: bid.offeredAmountOut,
      estimatedFeeBPS: bid.estimatedFeeBPS,
      targetChain: bid.targetChain,
      maxGasBid: bid.maxGasBid,
      strategy: bid.strategy,
      submittedAt: bid.submittedAt,
      score: bid.score
    )
  }
  return nil
}
`;

// ── Public API ────────────────────────────────────────────────────────────────

export async function getTotalIntents(): Promise<number> {
  return executeScript(GET_TOTAL_INTENTS_SCRIPT, []);
}

export async function getOpenIntentIds(): Promise<number[]> {
  const result = await executeScript(GET_OPEN_INTENTS_SCRIPT, []);
  return Array.isArray(result) ? result : [];
}

export async function getIntent(id: number): Promise<Intent | null> {
  const result = await executeScript(GET_INTENT_FULL_SCRIPT, [
    { type: "UInt64", value: id.toString() },
  ]);
  if (result === null || result === undefined) return null;
  return {
    id: result.id ?? id,
    intentOwner: result.intentOwner ?? "",
    principalAmount: result.principalAmount ?? 0,
    intentType: result.intentType ?? 0,
    targetAPY: result.targetAPY ?? 0,
    minAmountOut: result.minAmountOut ?? null,
    maxFeeBPS: result.maxFeeBPS ?? null,
    durationDays: result.durationDays ?? 0,
    expiryBlock: result.expiryBlock ?? 0,
    status: result.status ?? 0,
    winningBidID: result.winningBidID ?? null,
    createdAt: result.createdAt ?? 0,
    principalSide: result.principalSide ?? 0,
    gasEscrowBalance: result.gasEscrowBalance ?? 0,
    executionDeadlineBlock: result.executionDeadlineBlock ?? 0,
  };
}

export async function getBidsForIntent(intentID: number): Promise<number[]> {
  const result = await executeScript(GET_BIDS_FOR_INTENT_SCRIPT, [
    { type: "UInt64", value: intentID.toString() },
  ]);
  return Array.isArray(result) ? result : [];
}

export async function getBid(bidID: number): Promise<Bid | null> {
  const result = await executeScript(GET_BID_SCRIPT, [
    { type: "UInt64", value: bidID.toString() },
  ]);
  if (result === null || result === undefined) return null;
  return {
    id: result.id ?? bidID,
    intentID: result.intentID ?? 0,
    solverAddress: result.solverAddress ?? "",
    solverEVMAddress: result.solverEVMAddress ?? "",
    offeredAPY: result.offeredAPY ?? null,
    offeredAmountOut: result.offeredAmountOut ?? null,
    estimatedFeeBPS: result.estimatedFeeBPS ?? null,
    targetChain: result.targetChain ?? null,
    maxGasBid: result.maxGasBid ?? 0,
    strategy: result.strategy ?? "",
    submittedAt: result.submittedAt ?? 0,
    score: result.score ?? 0,
  };
}

export async function getBidsBySolver(solverAddress: string): Promise<number[]> {
  const script = `
    import BidManagerV0_3 from ${DEPLOYER}
    access(all) fun main(solver: Address): [UInt64] {
      return BidManagerV0_3.getBidsBySolver(solver)
    }
  `
  const result = await executeScript(script, [
    { type: "Address", value: solverAddress },
  ])
  return (Array.isArray(result) ? result : []) as number[]
}

export async function getBidsByIds(bidIds: number[]): Promise<Bid[]> {
  const bids = await Promise.all(bidIds.map((id) => getBid(id)))
  return bids.filter(Boolean) as Bid[]
}

export async function getWinningBidForIntent(intentID: number): Promise<Bid | null> {
  const result = await executeScript(GET_WINNING_BID_SCRIPT, [
    { type: "UInt64", value: intentID.toString() },
  ]);
  if (result === null || result === undefined) return null;
  return {
    id: result.id ?? 0,
    intentID: result.intentID ?? intentID,
    solverAddress: result.solverAddress ?? "",
    solverEVMAddress: result.solverEVMAddress ?? "",
    offeredAPY: result.offeredAPY ?? null,
    offeredAmountOut: result.offeredAmountOut ?? null,
    estimatedFeeBPS: result.estimatedFeeBPS ?? null,
    targetChain: result.targetChain ?? null,
    maxGasBid: result.maxGasBid ?? 0,
    strategy: result.strategy ?? "",
    submittedAt: result.submittedAt ?? 0,
    score: result.score ?? 0,
  };
}

export async function getCurrentBlockHeight(): Promise<number> {
  const res = await fetch(`${ACCESS_NODE}/v1/blocks?height=sealed`);
  if (!res.ok) throw new Error(`Failed to get block: ${res.status}`);
  const data = await res.json();
  return parseInt(data[0].header.height, 10);
}

// ── Protocol stats (events + scripts) ────────────────────────────────────────

export interface ProtocolStats {
  totalIntents: number;
  openIntents: number;
  executedIntents: number;
  totalVolumeFlow: number;
}

async function queryEvents(
  eventType: string,
  startBlock: number,
  endBlock: number
): Promise<unknown[]> {
  const CHUNK = 250;
  const allEvents: unknown[] = [];

  for (let start = startBlock; start <= endBlock; start += CHUNK) {
    const end = Math.min(start + CHUNK - 1, endBlock);
    try {
      const res = await fetch(
        `${ACCESS_NODE}/v1/events?type=${encodeURIComponent(eventType)}&start_height=${start}&end_height=${end}`
      );
      if (!res.ok) continue;
      const data = await res.json();
      // data is an array of block event results, each with .events array
      if (Array.isArray(data)) {
        for (const blockResult of data) {
          if (Array.isArray(blockResult.events)) {
            allEvents.push(...blockResult.events);
          }
        }
      }
    } catch {
      // continue on chunk errors
    }
  }
  return allEvents;
}

export async function getProtocolStats(): Promise<ProtocolStats> {
  try {
    const [totalIntents, openIds, currentHeight] = await Promise.all([
      getTotalIntents(),
      getOpenIntentIds(),
      getCurrentBlockHeight(),
    ]);

    // Query last 5000 blocks for events (~12h on Flow, reasonable for stats)
    const startBlock = Math.max(1, currentHeight - 5000);

    const [createdEvents, executedEvents] = await Promise.all([
      queryEvents(
        `A.c65395858a38d8ff.IntentMarketplaceV0_3.IntentCreated`,
        startBlock,
        currentHeight
      ),
      queryEvents(
        `A.c65395858a38d8ff.IntentExecutorV0_3.IntentExecuted`,
        startBlock,
        currentHeight
      ),
    ]);

    // Sum volume from IntentCreated events
    let totalVolumeFlow = 0;
    for (const evt of createdEvents) {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const e = evt as any;
        // Event payload is base64-encoded JSON-CDC
        const payloadStr = Buffer.from(e.payload, "base64").toString();
        const parsed = JSON.parse(payloadStr);
        const fields = parsed?.value?.fields ?? [];
        const principalField = fields.find(
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (f: any) => f.name === "principalAmount"
        );
        if (principalField) {
          totalVolumeFlow += parseFloat(principalField.value?.value ?? "0");
        }
      } catch {
        // skip malformed events
      }
    }

    return {
      totalIntents,
      openIntents: openIds.length,
      executedIntents: executedEvents.length,
      totalVolumeFlow,
    };
  } catch (err) {
    console.error("getProtocolStats error:", err);
    // Return safe defaults on error
    return {
      totalIntents: 0,
      openIntents: 0,
      executedIntents: 0,
      totalVolumeFlow: 0,
    };
  }
}

// ── Intent type helpers ───────────────────────────────────────────────────────

// ── Live event feed ───────────────────────────────────────────────────────────

export type LiveEventType =
  | "IntentCreated"
  | "EVMIntentCreated"
  | "BidSubmitted"
  | "WinnerSelected"
  | "IntentCompleted"
  | "IntentCancelled";

export interface LiveEvent {
  id: string;
  eventType: LiveEventType;
  blockHeight: number;
  transactionId: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: Record<string, any>;
}

const LIVE_EVENT_SOURCES: { name: LiveEventType; contract: string }[] = [
  { name: "IntentCreated",    contract: "IntentMarketplaceV0_3" },
  { name: "EVMIntentCreated", contract: "IntentMarketplaceV0_3" },
  { name: "BidSubmitted",     contract: "BidManagerV0_3" },
  { name: "WinnerSelected",   contract: "BidManagerV0_3" },
  { name: "IntentCompleted",  contract: "IntentMarketplaceV0_3" },
  { name: "IntentCancelled",  contract: "IntentMarketplaceV0_3" },
];

export async function getRecentEvents(lookbackBlocks = 1000): Promise<LiveEvent[]> {
  const currentHeight = await getCurrentBlockHeight();
  const startBlock = Math.max(1, currentHeight - lookbackBlocks);

  const allResults = await Promise.all(
    LIVE_EVENT_SOURCES.map(async ({ name, contract }) => {
      const raw = await queryEvents(
        `A.c65395858a38d8ff.${contract}.${name}`,
        startBlock,
        currentHeight
      );
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (raw as any[]).map((e, i) => {
        try {
          const payloadStr = Buffer.from(e.payload, "base64").toString();
          const parsed = JSON.parse(payloadStr);
          const data = parseCDC(parsed) ?? {};
          return {
            id: `${e.block_height}-${e.transaction_id}-${i}`,
            eventType: name,
            blockHeight: parseInt(e.block_height, 10),
            transactionId: e.transaction_id as string,
            data,
          } as LiveEvent;
        } catch {
          return null;
        }
      }).filter(Boolean) as LiveEvent[];
    })
  );

  return allResults
    .flat()
    .sort((a, b) => b.blockHeight - a.blockHeight);
}

export function intentTypeLabel(intentType: number): "YIELD" | "SWAP" | "BRIDGE_YIELD" {
  if (intentType === 1) return "SWAP";
  if (intentType === 2) return "BRIDGE_YIELD";
  return "YIELD";
}

export function intentStatusLabel(status: number): string {
  switch (status) {
    case 0: return "Open";
    case 1: return "BidSelected";
    case 2: return "Active";
    case 3: return "Completed";
    case 4: return "Cancelled";
    case 5: return "Expired";
    default: return "Unknown";
  }
}
