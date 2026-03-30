import * as fcl from "@onflow/fcl";
import { FLOW_ACCESS_NODE } from "./constants";

export function configureFCL() {
  fcl.config({
    "flow.network": "mainnet",
    "accessNode.api": FLOW_ACCESS_NODE,
    "discovery.wallet": "https://fcl-discovery.onflow.org/authn",
    "app.detail.title": "FlowIntents",
    "app.detail.icon": "https://placekitten.com/g/200/200",
    "0xFungibleToken": "0xf233dcee88fe0abe",
    "0xFlowToken": "0x1654653399040a61",
    "0xIntentMarketplaceV0_3": "0xc65395858a38d8ff",
    "0xBidManagerV0_3": "0xc65395858a38d8ff",
    "0xIntentExecutorV0_3": "0xc65395858a38d8ff",
    "0xEVM": "0xe467b9dd11fa00df",
  });
}
