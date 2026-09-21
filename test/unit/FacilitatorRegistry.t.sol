// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FacilitatorRegistry} from "../../contracts/FacilitatorRegistry.sol";

contract FacilitatorRegistryTest is Test {
    FacilitatorRegistry internal registry;
    bytes32 internal constant ARB = keccak256("ARBITRAGE");
    bytes32 internal constant BRIDGE = keccak256("BRIDGE");
    address internal controller = address(0xC0DE);

    function setUp() public {
        registry = new FacilitatorRegistry(address(this), address(this));
        registry.grantRole(registry.CONTROLLER_ROLE(), controller);
        registry.addFacilitator(ARB, 100e18, 100, 900, 10_000);
        registry.addFacilitator(BRIDGE, 50e18, 50, 900, 10_000);
    }

    function test_ControllerCanIncreaseAndDecreaseOutstanding() public {
        vm.startPrank(controller);
        registry.increaseOutstanding(ARB, 40e18);
        registry.increaseOutstanding(BRIDGE, 10e18);
        assertEq(registry.totalOutstanding(), 50e18);

        registry.decreaseOutstanding(ARB, 15e18);
        assertEq(registry.totalOutstanding(), 35e18);
        assertEq(registry.outstandingOf(ARB), 25e18);
        vm.stopPrank();
    }

    function test_BucketCannotExceedCapacity() public {
        vm.prank(controller);
        vm.expectRevert();
        registry.increaseOutstanding(ARB, 101e18);
    }

    function test_DisabledFacilitatorBlocksNewExposureButAllowsRepayment() public {
        vm.prank(controller);
        registry.increaseOutstanding(ARB, 20e18);

        registry.disableFacilitator(ARB);

        vm.prank(controller);
        vm.expectRevert();
        registry.increaseOutstanding(ARB, 1e18);

        vm.prank(controller);
        registry.decreaseOutstanding(ARB, 20e18);
        assertEq(registry.outstandingOf(ARB), 0);
    }

    function test_FacilitatorsAreIsolated() public {
        vm.prank(controller);
        registry.increaseOutstanding(ARB, 100e18);

        assertEq(registry.outstandingOf(BRIDGE), 0);
        assertEq(registry.remainingCapacity(BRIDGE), 50e18);
    }
}
