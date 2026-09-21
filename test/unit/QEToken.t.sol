// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {QEToken} from "../../contracts/token/QEToken.sol";

contract QETokenTest is Test {
    QEToken internal token;
    address internal controller = address(0xC0DE);
    address internal collateralAdapter = address(0xCA11);
    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new QEToken("QE Dollar", "QED", address(this));
        token.grantRole(token.QE_CONTROLLER_ROLE(), controller);
        token.grantRole(token.COLLATERAL_ADAPTER_ROLE(), collateralAdapter);
    }

    function test_QEControllerCanMintTemporarySupply() public {
        vm.prank(controller);
        token.qeMint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.totalSupply(), 100e18);
    }

    function test_CollateralAdapterCanMintCollateralBackedSupply() public {
        vm.prank(collateralAdapter);
        token.collateralMint(alice, 50e18);
        assertEq(token.balanceOf(alice), 50e18);
    }

    function test_AdminWithoutControllerRoleCannotQEMint() public {
        vm.expectRevert();
        token.qeMint(alice, 1e18);
    }

    function test_ControllerCanBurnFromAuthorizedHolder() public {
        vm.prank(controller);
        token.qeMint(controller, 10e18);

        vm.prank(controller);
        token.burnFromController(controller, 4e18);

        assertEq(token.balanceOf(controller), 6e18);
        assertEq(token.totalSupply(), 6e18);
    }

    function test_UnauthorizedAccountCannotBurnThroughControllerPath() public {
        vm.prank(controller);
        token.qeMint(alice, 10e18);

        vm.prank(alice);
        vm.expectRevert();
        token.burnFromController(alice, 1e18);
    }
}
