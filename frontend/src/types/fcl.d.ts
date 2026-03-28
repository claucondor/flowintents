declare module "@onflow/fcl" {
  export interface FlowUser {
    addr: string | null;
    loggedIn: boolean;
    cid?: string;
    expiresAt?: number;
    f_type?: string;
    f_vsn?: string;
    services?: unknown[];
  }

  export interface CurrentUser {
    subscribe: (callback: (user: FlowUser) => void) => () => void;
    snapshot: () => Promise<FlowUser>;
    authenticate: () => Promise<FlowUser>;
    unauthenticate: () => void;
  }

  export type ArgType = (value: unknown, type: unknown) => unknown;

  export interface T {
    UFix64: unknown;
    UInt64: unknown;
    UInt8: unknown;
    String: unknown;
    Bool: unknown;
    Address: unknown;
    Optional: (type: unknown) => unknown;
    Array: (type: unknown) => unknown;
  }

  export const t: T;
  export const arg: ArgType;

  export const currentUser: CurrentUser;

  export function authenticate(): Promise<FlowUser>;
  export function unauthenticate(): void;
  export function logIn(): Promise<FlowUser>;

  export function mutate(opts: {
    cadence: string;
    args?: (arg: ArgType, t: T) => unknown[];
    limit?: number;
    proposer?: unknown;
    authorizations?: unknown[];
    payer?: unknown;
  }): Promise<string>;

  export function query(opts: {
    cadence: string;
    args?: (arg: ArgType, t: T) => unknown[];
  }): Promise<unknown>;

  export function config(opts: Record<string, string>): void;

  export function send(interactions: unknown[]): Promise<unknown>;
  export function decode(response: unknown): Promise<unknown>;

  export function getBlock(isSealed?: boolean): unknown;
  export function getTransaction(txId: string): unknown;
  export function getTransactionStatus(txId: string): unknown;

  export function tx(txId: string): {
    onceSealed: () => Promise<unknown>;
    onceExecuted: () => Promise<unknown>;
    subscribe: (callback: (tx: unknown) => void) => () => void;
  };
}
