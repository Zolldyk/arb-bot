// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IUniswapV3SwapRouter
 * @notice Interface for Uniswap V3 Router to execute swaps
 * @dev This is a simplified interface with only the functions we need
 */

interface IUniswapV3SwapRouter {
    /**
     * @notice Params struct for exactInputSingle function
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param fee Fee tier of the pool (500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
     * @param recipient Address that will receive the output tokens
     * @param deadline Timestamp after which the transaction will revert
     * @param amountIn Amount of input tokens to send
     * @param amountOutMinimum Minimum amount of output tokens that must be received
     * @param sqrtPriceLimitX96 Price limit for the trade (0 for no limit)
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Swaps amountIn of tokenIn for as much tokenOut as possible
     * @param params The parameters for the swap
     * @return amountOut The amount of tokenOut received
     */
    
    function exactInputSingle(ExactInputSingleParams calldata params) 
        external 
        payable 
        returns (uint256 amountOut);
}