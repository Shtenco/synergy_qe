// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IQEToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function qeMint(address to, uint256 amount) external;
    function collateralMint(address to, uint256 amount) external;
    function burnFromController(address from, uint256 amount) external;
}
