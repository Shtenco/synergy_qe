// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQEToken} from "../interfaces/IQEToken.sol";

contract QEToken is ERC20, AccessControl, IQEToken {
    bytes32 public constant QE_CONTROLLER_ROLE = keccak256("QE_CONTROLLER_ROLE");
    bytes32 public constant COLLATERAL_ADAPTER_ROLE = keccak256("COLLATERAL_ADAPTER_ROLE");

    uint256 public override temporarySupply;

    error ZeroAddress();
    error ZeroAmount();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    ) ERC20(name_, symbol_) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function qeMint(address to, uint256 amount)
        external
        onlyRole(QE_CONTROLLER_ROLE)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        temporarySupply += amount;
        _mint(to, amount);
    }

    function collateralMint(address to, uint256 amount)
        external
        onlyRole(COLLATERAL_ADAPTER_ROLE)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }

    function burnFromController(address from, uint256 amount)
        external
        onlyRole(QE_CONTROLLER_ROLE)
    {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > temporarySupply) revert ZeroAmount();
        temporarySupply -= amount;
        _burn(from, amount);
    }
}
