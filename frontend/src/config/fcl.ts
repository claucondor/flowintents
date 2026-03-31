import * as fcl from "@onflow/fcl";
import { FLOW_ACCESS_NODE } from "./constants";

export function configureFCL() {
  fcl.config({
    "flow.network": "mainnet",
    "accessNode.api": FLOW_ACCESS_NODE,
    "discovery.wallet": "https://fcl-discovery.onflow.org/authn",
    "discovery.authn.endpoint": "https://fcl-discovery.onflow.org/api/authn",
    "app.detail.title": "FlowIntents",
    "app.detail.icon": "https://placekitten.com/g/200/200",
    "0xFungibleToken": "0xf233dcee88fe0abe",
    "0xFlowToken": "0x1654653399040a61",
    "0xIntentMarketplaceV0_3": "0xc65395858a38d8ff",
    "0xBidManagerV0_3": "0xc65395858a38d8ff",
    "0xIntentExecutorV0_3": "0xc65395858a38d8ff",
    "0xEVM": "0xe467b9dd11fa00df",
    // V0_4 contracts (user-executed intent model)
    "0xIntentMarketplaceV0_4": "0xc65395858a38d8ff",
    "0xBidManagerV0_4": "0xc65395858a38d8ff",
    "0xIntentExecutorV0_4": "0xc65395858a38d8ff",
    // Bridge contracts
    "0xFungibleTokenMetadataViews": "0xf233dcee88fe0abe",
    "0xViewResolver": "0x1d7e57aa55817448",
    "0xFlowEVMBridge": "0x1e4aa0b87d10b141",
    "0xFlowEVMBridgeConfig": "0x1e4aa0b87d10b141",
    "0xFlowEVMBridgeUtils": "0x1e4aa0b87d10b141",
    "0xScopedFTProviders": "0x1e4aa0b87d10b141",
  });
}
