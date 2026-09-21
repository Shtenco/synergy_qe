// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceAdapter} from "../interfaces/IPriceAdapter.sol";

contract MockPriceAdapter is IPriceAdapter {
    struct PriceData {
        uint256 priceUsd18;
        uint48 updatedAt;
    }

    mapping(address => PriceData) internal prices;

    function setPrice(address asset, uint256 priceUsd18, uint48 updatedAt) external {
        prices[asset] = PriceData(priceUsd18, updatedAt);
    }

    function getPrice(address asset) external view override returns (uint256 priceUsd18, uint48 updatedAt) {
        PriceData memory p = prices[asset];
        return (p.priceUsd18, p.updatedAt);
    }
}
