// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHardTreasury {
    function hardValue(address asset) external view returns (uint256);
    function hardNAV() external view returns (uint256);
    function externalLiabilitiesUsd18() external view returns (uint256);
    function expectedExitCostsUsd18() external view returns (uint256);
}
