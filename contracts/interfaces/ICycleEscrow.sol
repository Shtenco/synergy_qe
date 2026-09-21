// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CycleState} from "../types/QETypes.sol";

interface ICycleEscrow {
    function totalPrincipalOutstanding() external view returns (uint256);
    function principalOutstanding(uint256 cycleId) external view returns (uint256);
    function stateOf(uint256 cycleId) external view returns (CycleState);
    function facilitatorOf(uint256 cycleId) external view returns (bytes32);
    function createCycle(
        uint256 cycleId,
        bytes32 facilitatorId,
        uint256 principal,
        uint32 ttl,
        bytes32 routeHash
    ) external;
    function recordPrincipalBurn(uint256 cycleId, uint256 amount) external;
}
