"use client";

import React, { useState, useEffect } from "react";
import * as fcl from "@onflow/fcl";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { type MockIntent, shortenAddress, formatAmount } from "@/lib/utils";
import { getBidsForIntentV04, getBidV04, type Bid } from "@/lib/flow";
import { SELECT_WINNER_V04_TX } from "@/lib/cadence";

interface BidComparisonModalProps {
  open: boolean;
  onClose: () => void;
  intent: MockIntent;
  onSelectWinner?: (intentId: number) => void;
}

export function BidComparisonModal({
  open,
  onClose,
  intent,
  onSelectWinner,
}: BidComparisonModalProps) {
  const [bids, setBids] = useState<Bid[]>([]);
  const [loading, setLoading] = useState(false);
  const [selecting, setSelecting] = useState(false);
  const [txId, setTxId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Load bids when modal opens
  useEffect(() => {
    if (!open) return;
    setLoading(true);
    setError(null);
    getBidsForIntentV04(intent.id)
      .then((ids) => Promise.all(ids.map((id) => getBidV04(id))).then((bids) => bids.filter(Boolean) as Bid[]))
      .then((b) => setBids(b.sort((a, z) => z.score - a.score)))
      .catch(() => setError("Failed to load bids"))
      .finally(() => setLoading(false));
  }, [open, intent.id]);

  const bestBid = bids[0]; // highest score = first after sort

  const handleSelectWinner = async () => {
    setSelecting(true);
    setError(null);
    try {
      const id = await fcl.mutate({
        cadence: SELECT_WINNER_V04_TX,
        args: (arg: (v: string, t: unknown) => unknown, t: { UInt64: unknown }) => [
          arg(intent.id.toString(), t.UInt64),
        ],
        limit: 1000,
      });
      setTxId(id as string);
      await fcl.tx(id).onceSealed();
      onSelectWinner?.(intent.id);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Transaction failed");
    } finally {
      setSelecting(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`Bids · Intent #${intent.id}`}
      className="max-w-2xl"
    >
      {/* Intent summary */}
      <div className="mb-5 border border-[var(--border)] px-4 py-3 flex items-center justify-between">
        <span
          className="text-[10px] text-[var(--text-muted)] uppercase tracking-widest"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          {intent.type}
        </span>
        <span
          className="text-xs text-[var(--text-primary)]"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          {formatAmount(intent.amount)} FLOW ·{" "}
          {intent.type === "YIELD"
            ? `${intent.targetAPY}% target APY`
            : `→ ${intent.outputToken}`}
        </span>
      </div>

      {/* Explanation */}
      <p
        className="text-[10px] text-[var(--text-muted)] mb-4 leading-relaxed"
        style={{ fontFamily: "'Space Mono', monospace" }}
      >
        The contract auto-selects the highest-scoring bid. Scores are computed
        from offered APY/amount, gas bid, and solver history.
      </p>

      {loading ? (
        <div className="space-y-2 mb-5">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-12 bg-[var(--border)] rounded animate-pulse" />
          ))}
        </div>
      ) : error ? (
        <p className="text-red-400 text-sm text-center py-8 font-mono">{error}</p>
      ) : bids.length === 0 ? (
        <p
          className="text-[var(--text-muted)] text-center py-8 text-sm"
          style={{ fontFamily: "'Space Mono', monospace" }}
        >
          No bids received yet.
        </p>
      ) : (
        <>
          {/* Table header */}
          <div
            className="grid px-4 py-2 border-b border-[var(--border)] text-[10px] text-[var(--text-muted)] uppercase tracking-widest"
            style={{
              fontFamily: "'Space Mono', monospace",
              gridTemplateColumns: "1fr 110px 90px 70px 70px",
            }}
          >
            <div>Solver</div>
            <div>Offered</div>
            <div>Strategy</div>
            <div>Score</div>
            <div>Gas</div>
          </div>

          <div className="divide-y divide-[var(--border)] border border-t-0 border-[var(--border)] mb-5">
            {bids.map((bid) => {
              const isBest = bid.id === bestBid?.id;

              return (
                <div
                  key={bid.id}
                  className="grid px-4 py-3 items-center"
                  style={{
                    gridTemplateColumns: "1fr 110px 90px 70px 70px",
                    background: isBest ? "rgba(0,197,102,0.04)" : undefined,
                  }}
                >
                  {/* Solver */}
                  <div>
                    <div
                      className="text-xs text-[var(--text-primary)]"
                      style={{ fontFamily: "'Space Mono', monospace" }}
                    >
                      {shortenAddress(bid.solverAddress)}
                    </div>
                    {isBest && (
                      <div
                        className="text-[9px] text-[#00C566] mt-0.5"
                        style={{ fontFamily: "'Space Mono', monospace" }}
                      >
                        ★ Best Offer
                      </div>
                    )}
                  </div>

                  {/* Offered */}
                  <div>
                    {bid.offeredAPY != null ? (
                      <span
                        className="text-sm font-bold text-[#00C566]"
                        style={{ fontFamily: "'Space Mono', monospace" }}
                      >
                        {bid.offeredAPY.toFixed(2)}%
                      </span>
                    ) : bid.offeredAmountOut != null ? (
                      <span
                        className="text-sm font-bold text-[var(--text-primary)]"
                        style={{ fontFamily: "'Space Mono', monospace" }}
                      >
                        {formatAmount(bid.offeredAmountOut)}
                      </span>
                    ) : (
                      <span className="text-[var(--text-muted)] text-xs">—</span>
                    )}
                  </div>

                  {/* Strategy */}
                  <div
                    className="text-[10px] text-[var(--text-muted)] truncate"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                    title={bid.strategy}
                  >
                    {bid.strategy || "—"}
                  </div>

                  {/* Score */}
                  <div
                    className="text-xs font-bold tabular-nums"
                    style={{
                      fontFamily: "'Space Mono', monospace",
                      color: isBest ? "#00C566" : "var(--text-primary)",
                    }}
                  >
                    {bid.score.toFixed(3)}
                  </div>

                  {/* Gas */}
                  <div
                    className="text-[10px] text-[var(--text-muted)]"
                    style={{ fontFamily: "'Space Mono', monospace" }}
                  >
                    {bid.maxGasBid} FLOW
                  </div>
                </div>
              );
            })}
          </div>

          {intent.status === "Open" && onSelectWinner && (
            <div>
              {txId && (
                <p
                  className="text-[10px] text-[var(--text-muted)] text-center mb-2"
                  style={{ fontFamily: "'Space Mono', monospace" }}
                >
                  Tx: {txId.slice(0, 16)}… sealing…
                </p>
              )}
              {error && (
                <p className="text-[10px] text-red-400 text-center mb-2 font-mono">
                  {error}
                </p>
              )}
              <Button
                variant="primary"
                size="lg"
                onClick={handleSelectWinner}
                loading={selecting}
                className="w-full font-mono tracking-wide text-xs"
              >
                SELECT BEST BID →
              </Button>
              <p
                className="text-center text-[10px] text-[var(--text-muted)] mt-2"
                style={{ fontFamily: "'Space Mono', monospace" }}
              >
                Contract auto-selects highest score · you execute the winning strategy
              </p>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}
