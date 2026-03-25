// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title BuildWrapAndSwapStrategy
/// @notice Builds an ABI-encoded 3-step batch:
///   [0] WFLOW.deposit{value: 0.2 FLOW}()           — wrap 0.2 FLOW to WFLOW
///   [1] WFLOW.approve(ROUTER, 0.1 WFLOW)            — approve 0.1 WFLOW for swap
///   [2] ROUTER.swapExactTokensForTokens(            — swap 0.1 WFLOW -> stgUSDC
///         amountIn=0.1e18,
///         amountOutMin=<95% of getAmountsOut>,
///         path=[WFLOW, stgUSDC],
///         to=recipient,
///         deadline=block.timestamp+1800
///       )
///
/// The remaining 0.1 WFLOW (not swapped) stays in ComposerV4 and is swept
/// to the recipient address by ComposerV4.executeStrategyWithFunds(batch, recipient).
///
/// Addresses (Flow EVM mainnet, chainId 747):
///   WFLOW:   0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
///   stgUSDC: 0xF1815bd50389c46847f0Bda824eC8da914045D14
///   Router:  0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d
///
/// Usage:
///   # Test A (Cadence intent — recipient = COA EVM address):
///   RECIPIENT=0x000000000000000000000002858DdA8E37568bDf \
///     forge script evm/script/BuildWrapAndSwapStrategy.s.sol:BuildWrapAndSwapStrategy -vvv
///
///   # Test B (EVM intent — recipient = deployer EVM wallet):
///   RECIPIENT=0xA0cD6ffcb6577BcF654efeB5e8C3F4DB89FBcda3 \
///     forge script evm/script/BuildWrapAndSwapStrategy.s.sol:BuildWrapAndSwapStrategy -vvv
///
/// minAmountOut: 95% of getAmountsOut(0.1e18, [WFLOW, stgUSDC]) at current reserves.
///   At observed reserves: 0.1 WFLOW -> ~3138 stgUSDC units => minOut = 2981
contract BuildWrapAndSwapStrategy is Script {
    address constant WFLOW   = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address constant STGUSDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address constant ROUTER  = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;

    // Selectors
    bytes4 constant DEPOSIT_SELECTOR  = 0xd0e30db0; // WFLOW.deposit()
    bytes4 constant APPROVE_SELECTOR  = 0x095ea7b3; // ERC20.approve(address,uint256)
    bytes4 constant SWAP_SELECTOR     = 0x38ed1739; // swapExactTokensForTokens(uint256,uint256,address[],address,uint256)

    struct StrategyStep {
        uint8   protocol; // 4 = CUSTOM
        address target;
        bytes   callData;
        uint256 value;    // attoFLOW (non-zero only for deposit step)
    }

    function run() external view {
        // Recipient: set via RECIPIENT env var, fallback to COA address
        address recipient = vm.envOr(
            "RECIPIENT",
            address(0x000000000000000000000002858DdA8E37568bDf)
        );

        uint256 wrapAmount  = 0.2 ether;  // 0.2 FLOW to wrap
        uint256 swapAmount  = 0.1 ether;  // 0.1 WFLOW to swap (0.1 WFLOW stays as output)
        uint256 minAmountOut = 2981;       // 95% of observed 3138 stgUSDC units
        // Use far-future deadline (year 2100) so batch doesn't expire
        // PunchSwap checks deadline >= block.timestamp, using max uint avoids all expiry issues
        uint256 deadline    = 4102444800; // 2100-01-01 00:00:00 UTC

        // Build swap path
        address[] memory path = new address[](2);
        path[0] = WFLOW;
        path[1] = STGUSDC;

        StrategyStep[] memory steps = new StrategyStep[](3);

        // Step 0: wrap 0.2 FLOW -> WFLOW via deposit()
        steps[0] = StrategyStep({
            protocol: 4,       // CUSTOM
            target:   WFLOW,
            callData: abi.encodeWithSelector(DEPOSIT_SELECTOR),
            value:    wrapAmount
        });

        // Step 1: approve PunchSwap router to spend 0.1 WFLOW
        steps[1] = StrategyStep({
            protocol: 4,       // CUSTOM
            target:   WFLOW,
            callData: abi.encodeWithSelector(APPROVE_SELECTOR, ROUTER, swapAmount),
            value:    0
        });

        // Step 2: swap 0.1 WFLOW -> stgUSDC, output goes directly to recipient
        steps[2] = StrategyStep({
            protocol: 4,       // CUSTOM
            target:   ROUTER,
            callData: abi.encodeWithSelector(
                SWAP_SELECTOR,
                swapAmount,      // amountIn: 0.1 WFLOW
                minAmountOut,    // amountOutMin: 2981 stgUSDC units (~95% of observed)
                path,            // path: [WFLOW, stgUSDC]
                recipient,       // to: recipient receives stgUSDC directly
                deadline         // deadline: block.timestamp + 1800
            ),
            value: 0
        });

        bytes memory encodedBatch = abi.encode(steps);

        console2.log("=== WrapAndSwap Strategy: 0.2 FLOW -> 0.1 WFLOW + stgUSDC ===");
        console2.log("WFLOW:      ", WFLOW);
        console2.log("stgUSDC:    ", STGUSDC);
        console2.log("Router:     ", ROUTER);
        console2.log("recipient:  ", recipient);
        console2.log("wrapAmount: ", wrapAmount, " (0.2 FLOW)");
        console2.log("swapAmount: ", swapAmount, " (0.1 WFLOW)");
        console2.log("minOut:     ", minAmountOut, " stgUSDC units (6 decimals)");
        console2.log("");
        console2.log("Steps:");
        console2.log("  [0] CUSTOM - WFLOW.deposit{value: 0.2 FLOW}()");
        console2.log("  [1] CUSTOM - WFLOW.approve(ROUTER, 0.1e18)");
        console2.log("  [2] CUSTOM - ROUTER.swapExactTokensForTokens(0.1e18, 2981, [WFLOW,stgUSDC], recipient, deadline)");
        console2.log("");
        console2.log("After execution:");
        console2.log("  - stgUSDC -> recipient (via swap `to` param)");
        console2.log("  - 0.1 WFLOW remaining -> swept to recipient by ComposerV4");
        console2.log("");
        console2.log("encodedBatch (hex):");
        console2.logBytes(encodedBatch);
    }
}
