// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @title IFlashLoanRecipient
 * @notice Interface that flash loan recipients must implement
 * @dev This is the correct interface for Balancer V2 flash loans
 */
interface IFlashLoanRecipient {
    /**
     * @notice Receive flash loan callback
     * @param tokens Array of tokens that were borrowed
     * @param amounts Array of amounts that were borrowed
     * @param feeAmounts Array of fee amounts to be paid
     * @param userData Arbitrary data passed from the flash loan initiator
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

/**
 * @title IBalancerVault
 * @notice Interface for Balancer Vault to execute flash loans
 * @dev Updated interface with correct function signature
 */
interface IBalancerVault {
    /**
     * @notice Flash loan function that lends tokens to a recipient and executes a callback
     * @param recipient Address of contract receiving the flash loan (must implement IFlashLoanRecipient)
     * @param tokens Array of token addresses to be lent
     * @param amounts Array of amounts to be lent for each token
     * @param userData Arbitrary data to pass to the receiver
     */
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}
