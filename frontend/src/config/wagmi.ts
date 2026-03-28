import { http, createConfig } from "wagmi";
import { defineChain } from "viem";
import { injected } from "wagmi/connectors";
import { FLOW_EVM_RPC, FLOW_CHAIN_ID } from "./constants";

export const flowEVM = defineChain({
  id: FLOW_CHAIN_ID,
  name: "Flow EVM",
  nativeCurrency: { name: "Flow", symbol: "FLOW", decimals: 18 },
  rpcUrls: {
    default: { http: [FLOW_EVM_RPC] },
  },
  blockExplorers: {
    default: {
      name: "Flowscan",
      url: "https://evm.flowscan.io",
    },
  },
});

export const wagmiConfig = createConfig({
  chains: [flowEVM],
  connectors: [injected()],
  transports: {
    [FLOW_CHAIN_ID]: http(FLOW_EVM_RPC),
  },
});
