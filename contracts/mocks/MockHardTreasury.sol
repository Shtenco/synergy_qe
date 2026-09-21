// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHardTreasury} from "../interfaces/IHardTreasury.sol";

contract MockHardTreasury is IHardTreasury {
    uint256 internal nav;
    uint256 public override externalLiabilitiesUsd18;
    uint256 public override expectedExitCostsUsd18;

    function setHardNAV(uint256 value) external {
        nav = value;
    }

    function hardValue(address) external pure override returns (uint256) {
        return 0;
    }

    function hardNAV() external view override returns (uint256) {
        return nav;
    }

    function isEndogenous(address) external pure override returns (bool) {
        return false;
    }
}
