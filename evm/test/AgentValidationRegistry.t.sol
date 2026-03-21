// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AgentValidationRegistry} from "../src/AgentValidationRegistry.sol";
import {AgentReputationRegistry} from "../src/AgentReputationRegistry.sol";
import {IAgentValidationRegistry} from "../src/interfaces/IAgentValidationRegistry.sol";

contract AgentValidationRegistryTest is Test {
    AgentValidationRegistry public validationReg;
    AgentReputationRegistry public reputationReg;

    address public owner  = makeAddr("owner");
    address public coa1   = address(0x0000000000000000000000020000000000000001);
    address public coa2   = address(0x0000000000000000000000020000000000000002);
    address public nonCOA = makeAddr("nonCOA");

    bytes32 constant EVIDENCE = keccak256("execution_proof_v1");

    function setUp() public {
        // Deploy reputation first (needs validation address — use address(0) placeholder, set later)
        vm.startPrank(owner);
        // Use a two-step setup: deploy reputation with a placeholder, then deploy validation
        // and update the pointer. For tests we use the final pattern from Deploy.s.sol

        // Step 1: deploy validation reg with a dummy reputation (we'll update)
        reputationReg  = new AgentReputationRegistry(owner, address(1)); // placeholder
        validationReg  = new AgentValidationRegistry(owner, address(reputationReg));

        // Step 2: update reputation's validation registry pointer
        reputationReg.setValidationRegistry(address(validationReg));

        // Authorize coa1
        validationReg.authorizeCOA(coa1);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Access control
    // -------------------------------------------------------------------------

    function test_OnlyCOA_CanRecordValidation() public {
        vm.prank(nonCOA);
        vm.expectRevert("AgentValidationRegistry: caller is not authorized COA");
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);
    }

    function test_AuthorizedCOA_CanRecord() public {
        vm.prank(coa1);
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);

        IAgentValidationRegistry.ValidationRecord memory record =
            validationReg.getValidation(1);
        assertTrue(record.exists);
    }

    function test_UnauthorizedCOA_Reverts() public {
        vm.prank(coa2); // not authorized
        vm.expectRevert("AgentValidationRegistry: caller is not authorized COA");
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);
    }

    // -------------------------------------------------------------------------
    // Immutability
    // -------------------------------------------------------------------------

    function test_CannotValidate_SameIntentTwice() public {
        vm.startPrank(coa1);
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);

        vm.expectRevert("AgentValidationRegistry: intent already validated");
        validationReg.recordValidation(1, 1, 200e18, 20e18, EVIDENCE);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Record contents
    // -------------------------------------------------------------------------

    function test_ValidationRecord_StoredCorrectly() public {
        vm.prank(coa1);
        validationReg.recordValidation(42, 7, 500e18, 50e18, EVIDENCE);

        IAgentValidationRegistry.ValidationRecord memory r =
            validationReg.getValidation(42);

        assertEq(r.intentId, 42);
        assertEq(r.solverTokenId, 7);
        assertEq(r.principalReturned, 500e18);
        assertEq(r.yieldEarned, 50e18);
        assertEq(r.evidenceHash, EVIDENCE);
        assertTrue(r.exists);
        assertGt(r.timestamp, 0);
    }

    function test_GetValidation_NonExistent_ReturnsFalse() public view {
        IAgentValidationRegistry.ValidationRecord memory r =
            validationReg.getValidation(999);
        assertFalse(r.exists);
    }

    // -------------------------------------------------------------------------
    // Integration: reputation update
    // -------------------------------------------------------------------------

    function test_RecordValidation_UpdatesReputation_Success() public {
        uint256 scoreBefore = reputationReg.getScore(1);

        vm.prank(coa1);
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);

        uint256 scoreAfter = reputationReg.getScore(1);
        assertEq(scoreAfter, scoreBefore + 10e18);
    }

    function test_RecordValidation_UpdatesReputation_Failure() public {
        uint256 scoreBefore = reputationReg.getScore(1);

        // evidenceHash = bytes32(0) → interpreted as failure
        vm.prank(coa1);
        validationReg.recordValidation(1, 1, 0, 0, bytes32(0));

        uint256 scoreAfter = reputationReg.getScore(1);
        assertEq(scoreAfter, scoreBefore - 20e18);
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    function test_IntentValidated_Event_Success() public {
        vm.expectEmit(true, true, false, true);
        emit IAgentValidationRegistry.IntentValidated(1, 7, true);

        vm.prank(coa1);
        validationReg.recordValidation(1, 7, 100e18, 10e18, EVIDENCE);
    }

    function test_IntentValidated_Event_Failure() public {
        vm.expectEmit(true, true, false, true);
        emit IAgentValidationRegistry.IntentValidated(1, 7, false);

        vm.prank(coa1);
        validationReg.recordValidation(1, 7, 0, 0, bytes32(0));
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function test_AuthorizeCOA_OnlyOwner() public {
        vm.prank(nonCOA);
        vm.expectRevert();
        validationReg.authorizeCOA(coa2);
    }

    function test_RevokeCOA_PreventsAccess() public {
        vm.prank(owner);
        validationReg.authorizeCOA(coa2);

        vm.prank(owner);
        validationReg.revokeCOA(coa2);

        vm.prank(coa2);
        vm.expectRevert("AgentValidationRegistry: caller is not authorized COA");
        validationReg.recordValidation(1, 1, 100e18, 10e18, EVIDENCE);
    }
}
