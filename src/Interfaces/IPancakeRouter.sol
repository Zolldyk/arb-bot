// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPancakeRouter
 * @notice Interface for PancakeSwap Router to execute swaps
 * @dev This is a simplified interface with only the functions we need
 */

interface IPancakeRouter {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param path Array of token addresses (path[0] = input token, path[path.length-1] = output token)
     * @param to Address that will receive the output tokens
     * @param deadline Timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}