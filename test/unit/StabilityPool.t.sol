// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StabilityPool} from "../../contracts/StabilityPool.sol";
import {HardTreasury} from "../../contracts/HardTreasury.sol";
import {OracleRouter} from "../../contracts/OracleRouter.sol";
import {QEToken} from "../../contracts/token/QEToken.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {MockPriceAdapter} from "../../contracts/mocks/MockPriceAdapter.sol";
import {MockUnwindAdapter} from "../../contracts/mocks/MockUnwindAdapter.sol";

contract StabilityPoolTest is Test {
    StabilityPool internal pool;
    HardTreasury internal treasury;
    OracleRouter internal router;
    MockERC20 internal usdc;
    QEToken internal qe;
    MockPriceAdapter internal oracle;
    MockPriceAdapter internal twap;
    MockUnwindAdapter internal unwind;

    address internal recipient = address(0xBEEF);

    function setUp() public {
        vm.warp(1_000);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        qe = new QEToken("QE Dollar", "QED", address(this));
        oracle = new MockPriceAdapter();
        twap = new MockPriceAdapter();
        unwind = new MockUnwindAdapter();
        router = new OracleRouter(address(this), address(this));

        oracle.setPrice(address(usdc), 1e18, uint48(block.timestamp));
        twap.setPrice(address(usdc), 1e18, uint48(block.timestamp));
        unwind.setValue(address(usdc), 10_000_000, 10e18);
        unwind.setValue(address(usdc), 8_000_000, 8e18);

        router.registerAsset(
            address(usdc), 6, address(oracle), address(twap), address(unwind), 120, 100
        );

        address[] memory endogenous = new address[](1);
        endogenous[0] = address(qe);
        treasury = new HardTreasury(
            address(this), address(this), address(router), endogenous
        );

        pool = new StabilityPool(
            address(this),
            address(this),
            address(usdc),
            address(router),
            address(treasury)
        );

        usdc.mint(address(this), 10_000_000);
        usdc.approve(address(pool), type(uint256).max);
        pool.fund(10_000_000);
    }

    function test_AvailableLossBudgetUsesExternalExecutableValue() public view {
        assertEq(pool.availableLossBudgetUsd18(), 10e18);
    }

    function test_ReservedLossBudgetCannotBeWithdrawnAsExcess() public {
        pool.reserveLossBudget(2_000_000);

        vm.expectRevert();
        pool.withdrawExcess(address(this), 9_000_000);

        pool.withdrawExcess(address(this), 8_000_000);
        assertEq(usdc.balanceOf(address(pool)), 2_000_000);
    }

    function test_AbsorbLossSpendsRealReservedExternalAsset() public {
        pool.reserveLossBudget(2_000_000);
        pool.absorbLoss(recipient, 2_000_000);

        assertEq(usdc.balanceOf(recipient), 2_000_000);
        assertEq(pool.reservedLossAsset(), 0);
    }

    function test_CannotConstructPoolWithEndogenousLossAsset() public {
        vm.expectRevert();
        new StabilityPool(
            address(this),
            address(this),
            address(qe),
            address(router),
            address(treasury)
        );
    }
}
