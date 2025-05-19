// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice Mock ERC20 token for testing
 * @dev Extends OpenZeppelin's ERC20 with mint and burn functions for testing
 */
contract MockToken is ERC20 {
    uint8 private _decimals;
    
    /**
     * @notice Constructor for mock token
     * @param name Token name
     * @param symbol Token symbol
     * @param decimal Number of decimals
     */
    constructor(string memory name, string memory symbol, uint8 decimal) ERC20(name, symbol) {
        _decimals = decimal;
    }
    
    /**
     * @notice Override decimals function
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint tokens to an address
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    /**
     * @notice Burn tokens from an address
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}