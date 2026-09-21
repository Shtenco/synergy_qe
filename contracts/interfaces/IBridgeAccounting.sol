// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BridgeState} from "../types/QETypes.sol";

interface IBridgeAccounting {
    function claimHardValue(uint256 claimId) external view returns (uint256);
    function stateOf(uint256 claimId) external view returns (BridgeState);
}
