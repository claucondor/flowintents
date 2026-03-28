/**
 * chain.ts — Read intents from the Flow mainnet via the REST HTTP API.
 *
 * No signing required — all reads are Cadence scripts executed via POST.
 */

import { CADENCE_ADDRESSES } from "./config.js";

// ─── Types ────────────────────────────────────────────────────────────────────

export type IntentType = "Yield" | "Swap" | "BridgeYield" | "Unknown";
export type PrincipalSide = "cadence" | "evm";

export interface Intent {
  id: number;
  owner: string;
  intentType: IntentType;
  principalSide: PrincipalSide;
  tokenType: string;
  principalAmount: number;   // FLOW
  targetAPY: number;         // e.g. 5.0 means 5%
  minAmountOut: number | null;
  maxFeeBPS: number | null;
  durationDays: number;
  expiryBlock: number;
  createdAt: number;         // Unix timestamp
  recipientEVMAddress: string | null;
  gasEscrowBalance: number;  // FLOW
}

// ─── Cadence script helpers ───────────────────────────────────────────────────

async function runScript(cadence: string, args: unknown[] = []): Promise<unknown> {
  const url = `${CADENCE_ADDRESSES.FLOW_REST_API}/v1/scripts`;
  const body = JSON.stringify({
    script: Buffer.from(cadence).toString("base64"),
    arguments: args.map((a) => Buffer.from(JSON.stringify(a)).toString("base64")),
  });

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });

  if (!res.ok) {
    throw new Error(`Flow script request failed: ${res.status} ${res.statusText}`);
  }

  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Failed to parse Flow script response: ${text.slice(0, 200)}`);
  }
}

// ─── Cadence JSON value decoders ─────────────────────────────────────────────

function decodeUInt64(val: unknown): number {
  if (typeof val === "object" && val !== null && "value" in val) {
    return parseInt((val as { value: string }).value, 10);
  }
  return 0;
}

function decodeUFix64(val: unknown): number {
  if (typeof val === "object" && val !== null && "value" in val) {
    return parseFloat((val as { value: string }).value);
  }
  return 0;
}

function decodeString(val: unknown): string {
  if (typeof val === "object" && val !== null && "value" in val) {
    return String((val as { value: string }).value);
  }
  return "";
}

function decodeOptional<T>(val: unknown, decoder: (v: unknown) => T): T | null {
  if (typeof val === "object" && val !== null && "value" in val) {
    const inner = (val as { value: unknown }).value;
    if (inner === null || inner === undefined) return null;
    return decoder(inner);
  }
  return null;
}

function decodeAddress(val: unknown): string {
  if (typeof val === "object" && val !== null && "value" in val) {
    return String((val as { value: string }).value);
  }
  return "";
}

function decodeIntentType(val: unknown): IntentType {
  // Cadence enum value — rawValue field
  if (typeof val === "object" && val !== null && "value" in val) {
    const inner = val as { value: { fields?: Array<{ name: string; value: unknown }> } };
    // IntentType enum: Yield=0, Swap=1, BridgeYield=2
    const rawVal = inner.value?.fields?.find((f) => f.name === "rawValue");
    if (rawVal) {
      const raw = decodeUInt64(rawVal.value);
      if (raw === 0) return "Yield";
      if (raw === 1) return "Swap";
      if (raw === 2) return "BridgeYield";
    }
  }
  return "Unknown";
}

function decodePrincipalSide(val: unknown): PrincipalSide {
  if (typeof val === "object" && val !== null && "value" in val) {
    const inner = val as { value: { fields?: Array<{ name: string; value: unknown }> } };
    const rawVal = inner.value?.fields?.find((f) => f.name === "rawValue");
    if (rawVal) {
      const raw = decodeUInt64(rawVal.value);
      return raw === 0 ? "cadence" : "evm";
    }
  }
  return "cadence";
}

// ─── Get list of open intent IDs ─────────────────────────────────────────────

export async function getOpenIntentIds(): Promise<number[]> {
  const script = `
    import IntentMarketplaceV0_3 from 0xc65395858a38d8ff
    access(all) fun main(): [UInt64] {
      return IntentMarketplaceV0_3.getOpenIntents()
    }
  `;

  const result = await runScript(script) as { type?: string; value?: unknown[] };

  if (!result || result.type !== "Array" || !Array.isArray(result.value)) {
    console.warn("Unexpected response from getOpenIntents:", JSON.stringify(result).slice(0, 200));
    return [];
  }

  return result.value.map(decodeUInt64);
}

// ─── Get full intent details ──────────────────────────────────────────────────

export async function getIntentDetails(intentId: number): Promise<Intent | null> {
  const script = `
    import IntentMarketplaceV0_3 from 0xc65395858a38d8ff

    access(all) struct IntentView {
      access(all) let id: UInt64
      access(all) let owner: Address
      access(all) let intentType: IntentMarketplaceV0_3.IntentType
      access(all) let principalSide: IntentMarketplaceV0_3.PrincipalSide
      access(all) let tokenType: String
      access(all) let principalAmount: UFix64
      access(all) let targetAPY: UFix64
      access(all) let minAmountOut: UFix64?
      access(all) let maxFeeBPS: UInt64?
      access(all) let durationDays: UInt64
      access(all) let expiryBlock: UInt64
      access(all) let createdAt: UFix64
      access(all) let recipientEVMAddress: String?
      access(all) let gasEscrowBalance: UFix64

      init(
        id: UInt64, owner: Address, intentType: IntentMarketplaceV0_3.IntentType,
        principalSide: IntentMarketplaceV0_3.PrincipalSide,
        tokenType: String, principalAmount: UFix64, targetAPY: UFix64,
        minAmountOut: UFix64?, maxFeeBPS: UInt64?,
        durationDays: UInt64, expiryBlock: UInt64, createdAt: UFix64,
        recipientEVMAddress: String?, gasEscrowBalance: UFix64
      ) {
        self.id = id; self.owner = owner; self.intentType = intentType
        self.principalSide = principalSide; self.tokenType = tokenType
        self.principalAmount = principalAmount; self.targetAPY = targetAPY
        self.minAmountOut = minAmountOut; self.maxFeeBPS = maxFeeBPS
        self.durationDays = durationDays; self.expiryBlock = expiryBlock
        self.createdAt = createdAt; self.recipientEVMAddress = recipientEVMAddress
        self.gasEscrowBalance = gasEscrowBalance
      }
    }

    access(all) fun main(intentID: UInt64): IntentView? {
      if let intent = IntentMarketplaceV0_3.getIntent(id: intentID) {
        return IntentView(
          id: intent.id,
          owner: intent.intentOwner,
          intentType: intent.intentType,
          principalSide: intent.principalSide,
          tokenType: intent.tokenType.identifier,
          principalAmount: intent.principalAmount,
          targetAPY: intent.targetAPY,
          minAmountOut: intent.minAmountOut,
          maxFeeBPS: intent.maxFeeBPS,
          durationDays: intent.durationDays,
          expiryBlock: intent.expiryBlock,
          createdAt: intent.createdAt,
          recipientEVMAddress: intent.recipientEVMAddress,
          gasEscrowBalance: intent.getGasEscrowBalance()
        )
      }
      return nil
    }
  `;

  const argCadence = {
    type: "UInt64",
    value: String(intentId),
  };

  const result = await runScript(script, [argCadence]) as {
    type?: string;
    value?: { fields?: Array<{ name: string; value: unknown }> } | null;
  };

  if (!result || result.type === "Optional" && result.value === null) {
    return null;
  }

  // Result is Optional<IntentView>
  const outer = result as { type?: string; value?: unknown };
  let fields: Array<{ name: string; value: unknown }> | undefined;

  if (outer.type === "Optional") {
    const inner = outer.value as { type?: string; value?: { fields?: Array<{ name: string; value: unknown }> } };
    if (!inner || !inner.value) return null;
    fields = inner.value.fields;
  } else if (outer.type === "Struct") {
    const inner = outer as { value?: { fields?: Array<{ name: string; value: unknown }> } };
    fields = inner.value?.fields;
  }

  if (!fields) {
    console.warn("Could not parse intent fields from:", JSON.stringify(result).slice(0, 300));
    return null;
  }

  const get = (name: string) => fields!.find((f) => f.name === name)?.value;

  return {
    id: decodeUInt64(get("id")),
    owner: decodeAddress(get("owner")),
    intentType: decodeIntentType(get("intentType")),
    principalSide: decodePrincipalSide(get("principalSide")),
    tokenType: decodeString(get("tokenType")),
    principalAmount: decodeUFix64(get("principalAmount")),
    targetAPY: decodeUFix64(get("targetAPY")),
    minAmountOut: decodeOptional(get("minAmountOut"), decodeUFix64),
    maxFeeBPS: decodeOptional(get("maxFeeBPS"), decodeUInt64),
    durationDays: decodeUInt64(get("durationDays")),
    expiryBlock: decodeUInt64(get("expiryBlock")),
    createdAt: decodeUFix64(get("createdAt")),
    recipientEVMAddress: decodeOptional(get("recipientEVMAddress"), decodeString),
    gasEscrowBalance: decodeUFix64(get("gasEscrowBalance")),
  };
}

/**
 * Fetch all open intents with full details.
 * Returns an array of resolved Intent objects.
 */
export async function getOpenIntents(): Promise<Intent[]> {
  const ids = await getOpenIntentIds();
  if (ids.length === 0) return [];

  const results = await Promise.allSettled(ids.map(getIntentDetails));
  return results
    .filter((r): r is PromiseFulfilledResult<Intent | null> => r.status === "fulfilled")
    .map((r) => r.value)
    .filter((i): i is Intent => i !== null);
}
