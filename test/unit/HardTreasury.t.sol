// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HardTreasury} from "../../contracts/HardTreasury.sol";
import {OracleRouter} from "../../contracts/OracleRouter.sol";
import {QEToken} from "../../contracts/token/QEToken.sol";
import {MockPriceAdapter} from "../../contracts/mocks/MockPriceAdapter.sol";
import {MockUnwindAdapter} from "../../contracts/mocks/MockUnwindAdapter.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";

contract HardTreasuryTest is Test {
    HardTreasury internal treasury;
    OracleRouter internal router;
    QEToken internal qeToken;
    MockERC20 internal usdc;
    MockPriceAdapter internal oracle;
    MockPriceAdapter internal twap;
    MockUnwindAdapter internal unwind;

    function setUp() public {
        qeToken = new QEToken("QE Dollar", "QED", address(this));
        usdc = new MockERC20("USD Coin", "USDC", 6);

        oracle = new MockPriceAdapter();
        twap = new MockPriceAdapter();
        unwind = new MockUnwindAdapter();
        router = new OracleRouter(address(this), address(this));

        oracle.setPrice(address(usdc), 1e18, uint48(block.timestamp));
        twap.setPrice(address(usdc), 1e18, uint48(block.timestamp));
        unwind.setValue(address(usdc), 1_000_000, 1e18);
        unwind.setValue(address(usdc), 10_000_000, 10e18);
        unwind.setValue(address(usdc), 8_000_000, 8e18);

        router.registerAsset(
            address(usdc), 6, address(oracle), address(twap), address(unwind), 120, 100
        );

        address[] memory endogenous = new address[](1);
        endogenous[0] = address(qeToken);
        treasury = new HardTreasury(
            address(this), address(this), address(router), endogenous
        );
        treasury.registerAsset(address(usdc), 9_000, 10_000);
    }

    function test_ExternalAssetBalanceRaisesHardNAVWithHaircut() public {
        usdc.mint(address(treasury), 10_000_000);
        assertEq(treasury.hardNAV(), 9e18);
    }

    function test_EndogenousAssetCannotBeRegistered() public {
        vm.expectRevert();
        treasury.registerAsset(address(qeToken), 10_000, 10_000);
    }

    function test_ExternalLiabilityReducesHardNAV() public {
        usdc.mint(address(treasury), 10_000_000);
        treasury.increaseExternalLiability(2e18);
        assertEq(treasury.hardNAV(), 7e18);
    }

    function test_SettlementReservationRemovesReservedValueFromAvailableHardNAV() public {
        usdc.mint(address(treasury), 10_000_000);
        treasury.reserveForSettlement(address(usdc), 2_000_000);
        assertEq(treasury.hardNAV(), 72e17);
    }

    function test_ExitCostsReduceHardNAV() public {
        usdc.mint(address(treasury), 10_000_000);
        treasury.setExpectedExitCosts(1e18);
        assertEq(treasury.hardNAV(), 8e18);
    }

    function test_DisableAndReregisterCannotDoubleCountAsset() public {
        usdc.mint(address(treasury), 10_000_000);
        assertEq(treasury.hardNAV(), 9e18);

        treasury.disableAsset(address(usdc));
        treasury.registerAsset(address(usdc), 9_000, 10_000);

        assertEq(treasury.registeredAssetCount(), 1);
        assertEq(treasury.hardNAV(), 9e18);
    }
}
