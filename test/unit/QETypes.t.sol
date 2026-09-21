// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SystemMode, CycleState, BridgeState, QETypes} from "../../contracts/types/QETypes.sol";

contract QETypesTest is Test {
    function test_SystemModeOrderingIsStable() public pure {
        assertEq(uint256(SystemMode.NORMAL), 0);
        assertEq(uint256(SystemMode.DEFENSIVE), 1);
        assertEq(uint256(SystemMode.CONTRACTION), 2);
        assertEq(uint256(SystemMode.GLOBAL_SETTLEMENT), 3);
    }

    function test_CycleStateOrderingIsStable() public pure {
        assertEq(uint256(CycleState.NONE), 0);
        assertEq(uint256(CycleState.CREATED), 1);
        assertEq(uint256(CycleState.MINTED), 2);
        assertEq(uint256(CycleState.DEPLOYED), 3);
        assertEq(uint256(CycleState.RETURNED), 4);
        assertEq(uint256(CycleState.PRINCIPAL_BURNED), 5);
        assertEq(uint256(CycleState.SETTLED), 6);
        assertEq(uint256(CycleState.EXPIRED), 7);
        assertEq(uint256(CycleState.DEFAULTED), 8);
        assertEq(uint256(CycleState.EMERGENCY_SETTLED), 9);
    }

    function test_BridgeStateOrderingIsStable() public pure {
        assertEq(uint256(BridgeState.NONE), 0);
        assertEq(uint256(BridgeState.SOURCE_SETTLED), 1);
        assertEq(uint256(BridgeState.IN_FLIGHT), 2);
        assertEq(uint256(BridgeState.DESTINATION_SETTLED), 3);
        assertEq(uint256(BridgeState.FAILED), 4);
    }

    function test_CycleStructCanRepresentPrincipalAccounting() public pure {
        QETypes.Cycle memory cycle = QETypes.Cycle({
            facilitatorId: keccak256("ARBITRAGE"),
            state: CycleState.MINTED,
            principalMinted: 100e18,
            principalBurned: 40e18,
            externalValueInUsd18: 0,
            externalValueOutUsd18: 0,
            realizedPnlUsd18: 0,
            openedAt: 100,
            expiresAt: 200,
            routeHash: keccak256("route")
        });

        assertEq(cycle.principalMinted - cycle.principalBurned, 60e18);
    }
}
