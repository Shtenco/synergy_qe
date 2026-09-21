// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BridgeAccounting} from "../../contracts/BridgeAccounting.sol";
import {BridgeState} from "../../contracts/types/QETypes.sol";

contract BridgeAccountingTest is Test {
    BridgeAccounting internal bridge;
    address internal operator = address(0xB123);
    address internal asset = address(0x1001);

    function setUp() public {
        bridge = new BridgeAccounting(address(this), address(this), 8_000, 300);
        bridge.grantRole(bridge.BRIDGE_ROLE(), operator);
    }

    function test_SourceSettledCountsOnce() public {
        vm.prank(operator);
        bridge.openClaim(1, 8453, 1, asset, 1e18, 100e18, 120);

        assertEq(uint256(bridge.stateOf(1)), uint256(BridgeState.SOURCE_SETTLED));
        assertEq(bridge.claimHardValue(1), 100e18);
    }

    function test_InFlightUsesPendingHaircutNotSecondCopy() public {
        vm.startPrank(operator);
        bridge.openClaim(1, 8453, 1, asset, 1e18, 100e18, 120);
        bridge.markInFlight(1);
        vm.stopPrank();

        assertEq(uint256(bridge.stateOf(1)), uint256(BridgeState.IN_FLIGHT));
        assertEq(bridge.claimHardValue(1), 80e18);
    }

    function test_StaleInFlightClaimBecomesZero() public {
        vm.startPrank(operator);
        bridge.openClaim(1, 8453, 1, asset, 1e18, 100e18, 120);
        bridge.markInFlight(1);
        vm.stopPrank();

        vm.warp(block.timestamp + 301);
        assertEq(bridge.claimHardValue(1), 0);
    }

    function test_DestinationSettlementReplacesSourceClaim() public {
        vm.startPrank(operator);
        bridge.openClaim(1, 8453, 1, asset, 1e18, 100e18, 120);
        bridge.markInFlight(1);
        bridge.markDestinationSettled(1, 99e18, keccak256("dst-tx"));
        vm.stopPrank();

        assertEq(uint256(bridge.stateOf(1)), uint256(BridgeState.DESTINATION_SETTLED));
        assertEq(bridge.claimHardValue(1), 99e18);
    }

    function test_FailedClaimHasZeroHardValue() public {
        vm.startPrank(operator);
        bridge.openClaim(1, 8453, 1, asset, 1e18, 100e18, 120);
        bridge.markInFlight(1);
        bridge.markFailed(1);
        vm.stopPrank();

        assertEq(bridge.claimHardValue(1), 0);
    }
}
