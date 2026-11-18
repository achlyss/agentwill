// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AgentWill} from "../src/AgentWill.sol";
import {MockAgentID} from "../src/MockAgentID.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AgentWillTest is Test {
    AgentWill public will;
    MockAgentID public agentId;

    address public owner = makeAddr("owner");
    address public heir = makeAddr("heir");
    address public heir2 = makeAddr("heir2");
    address public stranger = makeAddr("stranger"); // never mints a mock ID
    address public deployer;

    uint256 constant INTERVAL = 30 days;
    uint256 constant GRACE = 7 days;
    string constant MESSAGE = "If you read this, I stopped checking in. Take care of the vault.";

    function setUp() public {
        deployer = address(this);
        agentId = new MockAgentID();
        will = new AgentWill(address(agentId));

        // owner + heir + heir2 hold a (mock) Agent ID; stranger does not.
        vm.prank(owner);
        agentId.mint();
        vm.prank(heir);
        agentId.mint();
        vm.prank(heir2);
        agentId.mint();
    }

    // -- helpers ----------------------------------------------------------

    function _createWill() internal returns (uint256 willId) {
        vm.prank(owner);
        willId = will.createWill(heir, INTERVAL, GRACE, MESSAGE);
    }

    function _createWillAs(address who, address h, uint256 interval, uint256 grace) internal returns (uint256) {
        vm.prank(who);
        return will.createWill(h, interval, grace, MESSAGE);
    }

    /// @dev readWill is access-controlled (owner / heir-after-release), so
    /// tests must read as the will owner; a bare call runs as this contract.
    function _readAsOwner(uint256 willId) internal returns (AgentWill.Will memory) {
        vm.prank(owner);
        return will.readWill(willId);
    }

    // -- createWill -------------------------------------------------------

    function test_CreateWill_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AgentWill.WillCreated(1, owner, heir, INTERVAL, GRACE, MESSAGE);
        uint256 willId = will.createWill(heir, INTERVAL, GRACE, MESSAGE);
        assertEq(willId, 1);
        assertEq(will.totalWills(), 1);

        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(w.owner, owner);
        assertEq(w.heir, heir);
        assertEq(w.checkInInterval, INTERVAL);
        assertEq(w.gracePeriod, GRACE);
        assertEq(w.lastCheckIn, block.timestamp);
        assertEq(uint256(w.status), uint256(AgentWill.Status.Active));
        assertEq(w.message, MESSAGE);
    }

    function test_CreateWill_RevertsForNonHolder() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotAgentIDHolder.selector, stranger));
        will.createWill(heir, INTERVAL, GRACE, MESSAGE);
    }

    function test_CreateWill_RevertsZeroHeir() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.InvalidHeir.selector, address(0)));
        will.createWill(address(0), INTERVAL, GRACE, MESSAGE);
    }

    function test_CreateWill_RevertsSelfAsHeir() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.InvalidHeir.selector, owner));
        will.createWill(owner, INTERVAL, GRACE, MESSAGE);
    }

    function test_CreateWill_RevertsZeroInterval() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.InvalidInterval.selector, 0));
        will.createWill(heir, 0, GRACE, MESSAGE);
    }

    function test_CreateWill_RevertsOversizedInterval() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(AgentWill.InvalidInterval.selector, 3651 days)
        );
        will.createWill(heir, 3651 days, GRACE, MESSAGE);
    }

    function test_CreateWill_RevertsOversizedGrace() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(AgentWill.InvalidGracePeriod.selector, 366 days)
        );
        will.createWill(heir, INTERVAL, 366 days, MESSAGE);
    }

    function test_CreateWill_MaxBoundsAllowed() public {
        uint256 willId = _createWillAs(owner, heir, 3650 days, 365 days);
        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(w.checkInInterval, 3650 days);
        assertEq(w.gracePeriod, 365 days);
    }

    function test_CreateWill_ZeroGraceAllowed() public {
        uint256 willId = _createWillAs(owner, heir, INTERVAL, 0);
        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(w.gracePeriod, 0);
    }

    function test_CreateWill_MultipleWillsPerOwner() public {
        uint256 id1 = _createWill();
        uint256 id2 = _createWillAs(owner, heir2, 7 days, 1 days);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(will.totalWills(), 2);

        uint256[] memory mine = will.getWillIdsByOwner(owner);
        assertEq(mine.length, 2);
        assertEq(mine[0], 1);
        assertEq(mine[1], 2);

        uint256[] memory forHeir = will.getWillIdsByHeir(heir);
        assertEq(forHeir.length, 1);
        assertEq(forHeir[0], 1);
    }

    function test_CreateWill_TracksAllIds() public {
        _createWill();
        _createWillAs(owner, heir2, 7 days, 1 days);
        uint256[] memory all = will.getAllWillIds();
        assertEq(all.length, 2);
        assertEq(all[0], 1);
        assertEq(all[1], 2);
    }

    function test_ReadWill_NonexistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillDoesNotExist.selector, 99));
        will.readWill(99);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillDoesNotExist.selector, 0));
        will.readWill(0);
    }

    // -- checkIn ----------------------------------------------------------

    function test_CheckIn_UpdatesTimestamp() public {
        uint256 willId = _createWill();
        uint256 createdAt = block.timestamp;
        vm.warp(createdAt + 10 days);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AgentWill.CheckedIn(willId, owner, createdAt + 10 days);
        will.checkIn(willId);

        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(w.lastCheckIn, createdAt + 10 days);
    }

    function test_CheckIn_RevertsForNonOwner() public {
        uint256 willId = _createWill();
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotWillOwner.selector, heir));
        will.checkIn(willId);
    }

    function test_CheckIn_RevertsWhenCancelled() public {
        uint256 willId = _createWill();
        vm.prank(owner);
        will.cancelWill(willId);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillNotActive.selector, willId));
        will.checkIn(willId);
    }

    function test_CheckIn_RevertsWhenReleased() public {
        uint256 willId = _createWill();
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(heir);
        will.releaseWill(willId);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillNotActive.selector, willId));
        will.checkIn(willId);
    }

    function test_CheckIn_ResetsDeadline() public {
        uint256 willId = _createWill();
        // 29 days in: not releasable. Check in, then 29 more days: still not releasable.
        vm.warp(block.timestamp + 29 days);
        assertFalse(will.isReleasable(willId));
        vm.prank(owner);
        will.checkIn(willId);
        vm.warp(block.timestamp + 29 days);
        assertFalse(will.isReleasable(willId));
        // 8 more days (past interval+grace since last check-in) -> releasable.
        vm.warp(block.timestamp + 8 days + 1);
        assertTrue(will.isReleasable(willId));
    }

    // -- releaseWill ------------------------------------------------------

    function test_Release_BeforeDeadlineReverts() public {
        uint256 willId = _createWill();
        vm.warp(block.timestamp + 10 days);
        uint256 releasableAt = block.timestamp + 0; // placeholder, computed below
        AgentWill.Will memory w = _readAsOwner(willId);
        releasableAt = w.lastCheckIn + INTERVAL + GRACE;
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotReleasableYet.selector, willId, releasableAt));
        will.releaseWill(willId);
    }

    function test_Release_AtExactDeadlineReverts() public {
        uint256 willId = _createWill();
        AgentWill.Will memory w = _readAsOwner(willId);
        uint256 releasableAt = w.lastCheckIn + INTERVAL + GRACE;
        vm.warp(releasableAt); // exactly at the boundary: NOT releasable (strict >)
        assertFalse(will.isReleasable(willId));
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotReleasableYet.selector, willId, releasableAt));
        will.releaseWill(willId);
    }

    function test_Release_OneSecondAfterDeadlineSucceeds() public {
        uint256 willId = _createWill();
        AgentWill.Will memory w = _readAsOwner(willId);
        vm.warp(w.lastCheckIn + INTERVAL + GRACE + 1);
        assertTrue(will.isReleasable(willId));

        vm.prank(heir);
        vm.expectEmit(true, true, false, true);
        emit AgentWill.WillReleased(willId, heir, block.timestamp);
        will.releaseWill(willId);

        AgentWill.Will memory released = _readAsOwner(willId);
        assertEq(uint256(released.status), uint256(AgentWill.Status.Released));
    }

    function test_Release_GracePeriodRespected() public {
        uint256 willId = _createWill();
        // Interval elapsed but grace not yet: not releasable.
        vm.warp(block.timestamp + INTERVAL + 1);
        assertFalse(will.isReleasable(willId));
        // Grace elapsed too: releasable.
        vm.warp(block.timestamp + GRACE);
        assertTrue(will.isReleasable(willId));
    }

    function test_Release_RevertsForNonHeir() public {
        uint256 willId = _createWill();
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotHeir.selector, owner));
        will.releaseWill(willId);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotHeir.selector, stranger));
        will.releaseWill(willId);
    }

    function test_Release_RevertsWhenHeirHasNoAgentID() public {
        // Heir without an Agent ID can be named at creation, but cannot release.
        address noIdHeir = makeAddr("noIdHeir");
        uint256 willId = _createWillAs(owner, noIdHeir, INTERVAL, GRACE);
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(noIdHeir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotAgentIDHolder.selector, noIdHeir));
        will.releaseWill(willId);
    }

    function test_Release_DoubleReleaseReverts() public {
        uint256 willId = _createWill();
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(heir);
        will.releaseWill(willId);
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillNotActive.selector, willId));
        will.releaseWill(willId);
    }

    function test_Release_AfterCancelReverts() public {
        uint256 willId = _createWill();
        vm.prank(owner);
        will.cancelWill(willId);
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillNotActive.selector, willId));
        will.releaseWill(willId);
    }

    // -- cancelWill -------------------------------------------------------

    function test_Cancel_Success() public {
        uint256 willId = _createWill();
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AgentWill.WillCancelled(willId, owner, block.timestamp);
        will.cancelWill(willId);
        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(uint256(w.status), uint256(AgentWill.Status.Cancelled));
    }

    function test_Cancel_RevertsForNonOwner() public {
        uint256 willId = _createWill();
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.NotWillOwner.selector, heir));
        will.cancelWill(willId);
    }

    function test_Cancel_DoubleCancelReverts() public {
        uint256 willId = _createWill();
        vm.prank(owner);
        will.cancelWill(willId);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.WillNotActive.selector, willId));
        will.cancelWill(willId);
    }

    // -- readWill access --------------------------------------------------

    function test_ReadWill_OwnerCanReadAnytime() public {
        uint256 willId = _createWill();
        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(w.owner, owner);
        // owner can still read after cancel
        vm.prank(owner);
        will.cancelWill(willId);
        AgentWill.Will memory w2 = _readAsOwner(willId);
        assertEq(uint256(w2.status), uint256(AgentWill.Status.Cancelled));
    }

    function test_ReadWill_HeirBeforeReleaseReverts() public {
        uint256 willId = _createWill();
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.CannotReadWill.selector, heir));
        will.readWill(willId);
    }

    function test_ReadWill_HeirAfterReleaseCanRead() public {
        uint256 willId = _createWill();
        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(heir);
        will.releaseWill(willId);
        vm.prank(heir);
        AgentWill.Will memory w = will.readWill(willId);
        assertEq(w.message, MESSAGE);
    }

    function test_ReadWill_StrangerReverts() public {
        uint256 willId = _createWill();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AgentWill.CannotReadWill.selector, stranger));
        will.readWill(willId);
    }

    function test_GetWillMeta_IsPublic() public {
        uint256 willId = _createWill();
        vm.prank(stranger);
        AgentWill.WillMeta memory m = will.getWillMeta(willId);
        assertEq(m.owner, owner);
        assertEq(m.heir, heir);
        assertEq(m.checkInInterval, INTERVAL);
        assertEq(m.gracePeriod, GRACE);
        assertEq(uint256(m.status), uint256(AgentWill.Status.Active));
        assertEq(m.releasableAt, m.lastCheckIn + INTERVAL + GRACE);
    }

    // -- pause ------------------------------------------------------------

    function test_Pause_BlocksMutatingFunctions() public {
        uint256 willId = _createWill();
        will.pause(); // deployer (this test contract) is the owner

        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        will.createWill(heir, INTERVAL, GRACE, MESSAGE);
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        will.checkIn(willId);
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        will.cancelWill(willId);

        vm.warp(block.timestamp + INTERVAL + GRACE + 1);
        vm.prank(heir);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        will.releaseWill(willId);

        // Views still work while paused.
        AgentWill.Will memory w = _readAsOwner(willId);
        assertEq(uint256(w.status), uint256(AgentWill.Status.Active));

        will.unpause();
        vm.prank(owner);
        will.checkIn(willId); // works again
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        will.pause();
    }

    // -- fuzz: deadline math ----------------------------------------------

    function testFuzz_ReleaseOnlyAfterDeadline(uint256 interval, uint256 grace, uint256 elapsed) public {
        interval = bound(interval, 1 hours, 365 days);
        grace = bound(grace, 0, 30 days);
        elapsed = bound(elapsed, 0, 400 days);

        uint256 willId = _createWillAs(owner, heir, interval, grace);
        AgentWill.Will memory w = _readAsOwner(willId);
        uint256 releasableAt = w.lastCheckIn + interval + grace;

        vm.warp(w.lastCheckIn + elapsed);
        bool expected = elapsed > interval + grace;
        assertEq(will.isReleasable(willId), expected);

        if (expected) {
            vm.prank(heir);
            will.releaseWill(willId);
            assertEq(uint256(_readAsOwner(willId).status), uint256(AgentWill.Status.Released));
        } else {
            vm.prank(heir);
            vm.expectRevert(
                abi.encodeWithSelector(AgentWill.NotReleasableYet.selector, willId, releasableAt)
            );
            will.releaseWill(willId);
        }
    }

    function testFuzz_CheckInAlwaysResetsClock(uint256 interval, uint256 grace) public {
        interval = bound(interval, 1 days, 90 days);
        grace = bound(grace, 0, 14 days);
        uint256 willId = _createWillAs(owner, heir, interval, grace);

        vm.warp(block.timestamp + interval + grace - 1); // 1s before releasable
        assertFalse(will.isReleasable(willId));
        vm.prank(owner);
        will.checkIn(willId);
        // Immediately after check-in: never releasable.
        assertFalse(will.isReleasable(willId));
        vm.warp(block.timestamp + interval + grace);
        assertFalse(will.isReleasable(willId)); // exactly at boundary: still not
        vm.warp(block.timestamp + 1);
        assertTrue(will.isReleasable(willId));
    }
}

/// @notice MockAgentID behaviour: 1 per wallet, soulbound.
contract MockAgentIDTest is Test {
    MockAgentID public agentId;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        agentId = new MockAgentID();
    }

    function test_MintOnce() public {
        vm.prank(alice);
        uint256 tokenId = agentId.mint();
        assertEq(tokenId, 1);
        assertEq(agentId.balanceOf(alice), 1);
        assertTrue(agentId.hasMinted(alice));
    }

    function test_MintTwiceReverts() public {
        vm.prank(alice);
        agentId.mint();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MockAgentID.AlreadyMinted.selector, alice));
        agentId.mint();
    }

    function test_TransferBlockedSoulbound() public {
        vm.prank(alice);
        uint256 tokenId = agentId.mint();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MockAgentID.Soulbound.selector));
        agentId.transferFrom(alice, bob, tokenId);
    }

    function test_BalanceOfZeroForNonHolder() public {
        assertEq(agentId.balanceOf(bob), 0);
    }
}
