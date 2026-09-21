// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUnwindAdapter {
    function quoteValue(address asset, uint256 amount) external view returns (uint256 valueUsd18);
}
