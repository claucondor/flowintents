// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildPunchSwapStrategy
/// @notice Helper script that prints the ABI-encoded batch for a WFLOW -> stgUSDC swap
///         via PunchSwap V2 (Uniswap V2 fork on Flow EVM mainnet).
///
/// PunchSwap V2 (Flow EVM mainnet):
///   Router:  0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d  (PunchSwapV2Router02)
///   Factory: 0x29372c22459a4e373851798bFd6808e71EA34A71  (PunchSwapV2Factory)
///   WFLOW:   0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e  (returned by router.WFLOW())
///
/// Active pairs (confirmed via getPair()):
///   WFLOW / stgUSDC : 0x83F9D1170967d46dd40447e6e66E1a58d2601124
///   WFLOW / USDC.e  : 0x4B07F2D19028A7fB7BF5E9258f9666a9673dA331
///   WFLOW / WETH    : 0x681A3c23E7704e5c90e45ABf800996145a8096fD
///   WFLOW / USDF    : 0x17e96496212d06Eb1Ff10C6f853669Cc9947A1e7
///   WFLOW / ankrFLOW: 0x442aE0F33d66F617AF9106e797fc251B574aEdb3
///   WFLOW / WBTC    : 0xAebc9efe5599D430Bc9045148992d3df50487ef2
///
/// Example output at current mainnet reserves (0.5 WFLOW):
///   -> stgUSDC : 14300  (decimals: 6 = $0.01430)
///   -> USDC.e  : 16112  (decimals: 6 = $0.01611)
///
/// 2-step strategy (requires solver to have already wrapped FLOW -> WFLOW):
///   [0] CUSTOM - WFLOW.approve(ROUTER, amount)
///   [1] CUSTOM - ROUTER.swapExactTokensForTokens(amountIn, minOut, path, to, deadline)
///
/// Usage:
///   forge script evm/script/BuildPunchSwapStrategy.s.sol:BuildPunchSwapStrategy -vvv
///
///   To specify a different output token or amount, modify the constants below.
contract BuildPunchSwapStrategy is Script {
    address constant ROUTER  = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address constant WFLOW   = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address constant STGUSDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address constant USDCE   = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52;

    // ERC-20 approve(address spender, uint256 amount)
    bytes4 constant APPROVE_SELECTOR = 0x095ea7b3;

    // swapExactTokensForTokens(uint256,uint256,address[],address,uint256)
    bytes4 constant SWAP_SELECTOR    = 0x38ed1739;

    struct StrategyStep {
        uint8   protocol; // 4 = CUSTOM
        address target;
        bytes   callData;
        uint256 value;    // 0 for ERC-20 calls
    }

    function run() external view {
        uint256 amountIn  = 0.5 ether;   // 0.5 WFLOW
        uint256 minOut    = 0;            // 0 = no slippage protection (set appropriately in prod)
        address receiver  = address(0xDEAD); // replace with intent user / COA address
        uint256 deadline  = block.timestamp + 1800; // 30 minutes

        // Build the swap path: WFLOW -> stgUSDC
        address[] memory path = new address[](2);
        path[0] = WFLOW;
        path[1] = STGUSDC;

        StrategyStep[] memory steps = new StrategyStep[](2);

        // Step 0: approve router to spend WFLOW
        steps[0] = StrategyStep({
            protocol: 4,    // CUSTOM
            target:   WFLOW,
            callData: abi.encodeWithSelector(APPROVE_SELECTOR, ROUTER, amountIn),
            value:    0
        });

        // Step 1: swap WFLOW for stgUSDC
        steps[1] = StrategyStep({
            protocol: 4,    // CUSTOM
            target:   ROUTER,
            callData: abi.encodeWithSelector(
                SWAP_SELECTOR,
                amountIn,   // amountIn
                minOut,     // amountOutMin (0 = no protection — set appropriately)
                path,       // path: [WFLOW, stgUSDC]
                receiver,   // to: recipient of output tokens
                deadline    // deadline
            ),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== PunchSwap V2 Swap Strategy: WFLOW -> stgUSDC ===");
        console2.log("Router:   ", ROUTER);
        console2.log("WFLOW:    ", WFLOW);
        console2.log("stgUSDC:  ", STGUSDC);
        console2.log("amountIn (attoFLOW/WFLOW):", amountIn);
        console2.log("receiver: ", receiver);
        console2.log("");
        console2.log("encodedBatch (hex) - 2-step: approve WFLOW + swapExactTokensForTokens:");
        console2.logBytes(encodedBatch);
        console2.log("");
        console2.log("Steps:");
        console2.log("  [0] CUSTOM - WFLOW.approve(ROUTER, amountIn)");
        console2.log("  [1] CUSTOM - ROUTER.swapExactTokensForTokens(amountIn, 0, [WFLOW,stgUSDC], receiver, deadline)");
        console2.log("");
        console2.log("Observed output at current reserves: 0.5 WFLOW -> ~14300 stgUSDC units ($0.01430 at 6 decimals)");
        console2.log("For better rates use WFLOW/USDC.e pair:  USDCE =", USDCE);
        console2.log("  0.5 WFLOW -> ~16112 USDC.e units at current reserves");
        console2.log("");
        console2.log("NOTE: This batch assumes WFLOW has already been wrapped from native FLOW.");
        console2.log("      For a full FLOW->WFLOW->stgUSDC strategy, prepend the BuildWFLOWStrategy batch steps.");
        console2.log("      minOut=0 has no slippage protection - set to getAmountsOut * 0.97 in production.");
        console2.log("      Rebuild per intent: amountIn, receiver, and deadline must be intent-specific.");
    }
}
