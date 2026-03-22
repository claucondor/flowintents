// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {IAgentIdentityRegistry} from "../src/interfaces/IAgentIdentityRegistry.sol";

contract AgentIdentityRegistryTest is Test {
    AgentIdentityRegistry public registry;

    address public owner  = makeAddr("owner");
    address public alice  = makeAddr("alice");
    address public bob    = makeAddr("bob");

    bytes32 public constant SOLVER_TYPE = keccak256("SOLVER");
    bytes32 public constant VALIDATOR_TYPE = keccak256("VALIDATOR");

    function setUp() public {
        vm.prank(owner);
        registry = new AgentIdentityRegistry(owner);
    }

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    function test_RegisterAgent_MintsToken() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");
        assertEq(tokenId, 1);
        assertEq(registry.ownerOf(tokenId), alice);
    }

    function test_RegisterAgent_SetsIdentity() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");

        IAgentIdentityRegistry.AgentIdentity memory id = registry.getIdentity(tokenId);
        assertEq(id.tokenId, tokenId);
        assertEq(id.owner, alice);
        assertEq(id.agentType, SOLVER_TYPE);
        assertEq(id.metadataURI, "ipfs://Qm123");
        assertTrue(id.active);
    }

    function test_RegisterAgent_OncePerAddress() public {
        vm.startPrank(alice);
        registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");
        vm.expectRevert("AgentIdentityRegistry: address already registered");
        registry.registerAgent(SOLVER_TYPE, "ipfs://Qm456");
        vm.stopPrank();
    }

    function test_TwoAddresses_RegisterSeparately() public {
        vm.prank(alice);
        uint256 aliceToken = registry.registerAgent(SOLVER_TYPE, "ipfs://alice");

        vm.prank(bob);
        uint256 bobToken = registry.registerAgent(VALIDATOR_TYPE, "ipfs://bob");

        assertEq(aliceToken, 1);
        assertEq(bobToken, 2);
        assertEq(registry.getTokenByOwner(alice), aliceToken);
        assertEq(registry.getTokenByOwner(bob), bobToken);
    }

    function test_GetTokenByOwner_ReturnsZero_ForUnregistered() public view {
        assertEq(registry.getTokenByOwner(alice), 0);
    }

    // -------------------------------------------------------------------------
    // isActive
    // -------------------------------------------------------------------------

    function test_IsActive_TrueAfterRegistration() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");
        assertTrue(registry.isActive(tokenId));
    }

    function test_IsActive_FalseForNonExistentToken() public view {
        assertFalse(registry.isActive(999));
    }

    function test_Deactivate_SetsInactive() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");

        vm.prank(alice);
        registry.deactivate(tokenId);

        assertFalse(registry.isActive(tokenId));
    }

    function test_Activate_SetsActive() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");

        vm.prank(alice);
        registry.deactivate(tokenId);

        vm.prank(alice);
        registry.activate(tokenId);

        assertTrue(registry.isActive(tokenId));
    }

    function test_Deactivate_NotOwner_Reverts() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");

        vm.prank(bob);
        vm.expectRevert("AgentIdentityRegistry: not token owner");
        registry.deactivate(tokenId);
    }

    // -------------------------------------------------------------------------
    // URI update
    // -------------------------------------------------------------------------

    function test_SetAgentURI_UpdatesURI() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://old");

        vm.prank(alice);
        registry.setAgentURI(tokenId, "ipfs://new");

        IAgentIdentityRegistry.AgentIdentity memory id = registry.getIdentity(tokenId);
        assertEq(id.metadataURI, "ipfs://new");
    }

    function test_SetAgentURI_NotOwner_Reverts() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://old");

        vm.prank(bob);
        vm.expectRevert("AgentIdentityRegistry: not token owner");
        registry.setAgentURI(tokenId, "ipfs://new");
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_SupportsInterface_ERC721() public view {
        assertTrue(registry.supportsInterface(0x80ac58cd)); // ERC-721
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(registry.supportsInterface(0x01ffc9a7)); // ERC-165
    }

    function test_SupportsInterface_ERC8004() public view {
        bytes4 erc8004Id = registry.ERC8004_INTERFACE_ID();
        assertTrue(registry.supportsInterface(erc8004Id));
    }

    // -------------------------------------------------------------------------
    // Transfer — ownerToToken mapping update
    // -------------------------------------------------------------------------

    function test_Transfer_UpdatesOwnerMapping() public {
        vm.prank(alice);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, "ipfs://Qm123");

        vm.prank(alice);
        registry.transferFrom(alice, bob, tokenId);

        assertEq(registry.getTokenByOwner(alice), 0);
        assertEq(registry.getTokenByOwner(bob), tokenId);
    }

    function test_Transfer_ToAddressWithToken_Reverts() public {
        vm.prank(alice);
        uint256 aliceToken = registry.registerAgent(SOLVER_TYPE, "ipfs://alice");

        vm.prank(bob);
        registry.registerAgent(VALIDATOR_TYPE, "ipfs://bob");

        vm.prank(alice);
        vm.expectRevert("AgentIdentityRegistry: destination already has a token");
        registry.transferFrom(alice, bob, aliceToken);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_Register_DifferentAddresses(address user, string calldata uri) public {
        vm.assume(user != address(0));
        vm.assume(user != alice && user != bob && user != owner);
        vm.assume(bytes(uri).length > 0 && bytes(uri).length < 200);
        // Filter out contract addresses — _safeMint will revert if recipient doesn't implement IERC721Receiver
        vm.assume(user.code.length == 0);

        vm.prank(user);
        uint256 tokenId = registry.registerAgent(SOLVER_TYPE, uri);

        assertGt(tokenId, 0);
        assertEq(registry.getTokenByOwner(user), tokenId);
        assertTrue(registry.isActive(tokenId));
    }
}
