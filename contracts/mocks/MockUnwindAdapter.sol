// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUnwindAdapter} from "../interfaces/IUnwindAdapter.sol";

contract MockUnwindAdapter is IUnwindAdapter {
    mapping(bytes32 => uint256) internal values;

    function setValue(address asset, uint256 amount, uint256 valueUsd18) external {
        values[keccak256(abi.encode(asset, amount))] = valueUsd18;
    }

    function quoteValue(address asset, uint256 amount) external view returns (uint256 valueUsd18) {
        return values[keccak256(abi.encode(asset, amount))];
    }
}
