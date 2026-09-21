// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OracleRouter} from "../../contracts/OracleRouter.sol";
import {MockPriceAdapter} from "../../contracts/mocks/MockPriceAdapter.sol";
import {MockUnwindAdapter} from "../../contracts/mocks/MockUnwindAdapter.sol";

contract OracleRouterTest is Test {
    OracleRouter internal router;
    MockPriceAdapter internal oracle;
    MockPriceAdapter internal twap;
    MockUnwindAdapter internal unwind;
    address internal asset = address(0x1001);

    function setUp() public {
        vm.warp(1_000);
        router = new OracleRouter(address(this), address(this));
        oracle = new MockPriceAdapter();
        twap = new MockPriceAdapter();
        unwind = new MockUnwindAdapter();

        oracle.setPrice(asset, 1e18, uint48(block.timestamp));
        twap.setPrice(asset, 99e16, uint48(block.timestamp));
        unwind.setValue(asset, 1_000_000, 98e16);

        router.registerAsset(
            asset,
            6,
            address(oracle),
            address(twap),
            address(unwind),
            120,
            500
        );
    }

    function test_UsesMinimumOfOracleTwapAndExecutableQuote() public view {
        uint256 value = router.conservativeValue(asset, 1_000_000);
        assertEq(value, 98e16);
    }

    function test_StaleIndependentOracleMakesValueZero() public {
        oracle.setPrice(asset, 1e18, uint48(block.timestamp - 121));
        assertEq(router.conservativeValue(asset, 1_000_000), 0);
    }

    function test_ExcessiveOracleTwapDivergenceMakesValueZero() public {
        twap.setPrice(asset, 8e17, uint48(block.timestamp));
        assertEq(router.conservativeValue(asset, 1_000_000), 0);
    }

    function test_GuardianCanDisableAsset() public {
        router.disableAsset(asset);
        assertEq(router.conservativeValue(asset, 1_000_000), 0);
    }

    function test_UnregisteredAssetHasZeroValue() public view {
        assertEq(router.conservativeValue(address(0xBAD), 1e18), 0);
    }
}
