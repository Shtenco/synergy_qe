// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SystemMode} from "../types/QETypes.sol";

interface IQEController {
    function totalOutstanding() external view returns (uint256);
    function mode() external view returns (SystemMode);

    function openTemporaryCycle(
        bytes32 facilitatorId,
        uint256 requestedAmount,
        bytes32 routeHash,
        address receiver
    ) external returns (uint256 cycleId);

    function burnTemporaryPrincipal(
        uint256 cycleId,
        address from,
        uint256 amount
    ) external;
}
