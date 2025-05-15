// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @title IBalancerVault
 * @notice Interface for Balancer Vault to execute flash loans
 * @dev This is a simplified interface with only the needed functions
 */

interface IBalancerVault {
    /**
     * @notice Flash loan function that lends tokens to a receiver and executes a callback
     * @param recipient Address of contract receiving the flash loan
     * @param tokens Array of token addresses to be lent
     * @param amounts Array of amounts to be lent for each token
     * @param userData Arbitrary data to pass to the receiver
     */
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}