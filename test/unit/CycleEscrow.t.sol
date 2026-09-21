// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleEscrow} from "../../contracts/CycleEscrow.sol";
import {CycleState} from "../../contracts/types/QETypes.sol";

contract CycleEscrowTest is Test {
    CycleEscrow internal escrow;
    address internal controller = address(0xC0DE);
    address internal facilitator = address(0xFA11);
    bytes32 internal constant ARB = keccak256("ARBITRAGE");

    function setUp() public {
        escrow = new CycleEscrow(address(this));
        escrow.grantRole(escrow.CONTROLLER_ROLE(), controller);
        escrow.grantRole(escrow.FACILITATOR_ROLE(), facilitator);
    }

    function test_CreateCycleRecordsPrincipalOutstanding() public {
        vm.prank(controller);
        escrow.createCycle(1, ARB, 100e18, 900, keccak256("route"));

        assertEq(escrow.totalPrincipalOutstanding(), 100e18);
        assertEq(escrow.principalOutstanding(1), 100e18);
        assertEq(uint256(escrow.stateOf(1)), uint256(CycleState.MINTED));
    }

    function test_BurnReducesExactCycleAndAggregateOutstanding() public {
        vm.prank(controller);
        escrow.createCycle(1, ARB, 100e18, 900, keccak256("route"));

        vm.prank(controller);
        escrow.recordPrincipalBurn(1, 35e18);

        assertEq(escrow.principalOutstanding(1), 65e18);
        assertEq(escrow.totalPrincipalOutstanding(), 65e18);
    }

    function test_CannotSettleBeforeFullPrincipalBurn() public {
        vm.prank(controller);
        escrow.createCycle(1, ARB, 100e18, 900, keccak256("route"));

        vm.prank(controller);
        vm.expectRevert();
        escrow.markSettled(1, 1e18);
    }

    function test_FullBurnAllowsSettlement() public {
        vm.prank(controller);
        escrow.createCycle(1, ARB, 100e18, 900, keccak256("route"));

        vm.startPrank(controller);
        escrow.recordPrincipalBurn(1, 100e18);
        escrow.markSettled(1, 2e18);
        vm.stopPrank();

        assertEq(escrow.totalPrincipalOutstanding(), 0);
        assertEq(uint256(escrow.stateOf(1)), uint256(CycleState.SETTLED));
    }

    function test_OnlyApprovedFacilitatorCanAdvanceRouteState() public {
        vm.prank(controller);
        escrow.createCycle(1, ARB, 100e18, 900, keccak256("route"));

        vm.prank(facilitator);
        escrow.markDeployed(1);

        vm.prank(facilitator);
        escrow.markReturned(1, 101e18);

        assertEq(uint256(escrow.stateOf(1)), uint256(CycleState.RETURNED));
    }
}
