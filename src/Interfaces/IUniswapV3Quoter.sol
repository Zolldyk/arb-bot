// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IUniswapV3Quoter
 * @notice Interface for Uniswap V3 Quoter contract to get price quotes
 */
interface IUniswapV3Quoter {
    /**
     * @notice Returns the amount out received for a given exact input swap without executing the swap
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param fee The fee tier of the pool to consider for the swap
     * @param amountIn The desired input amount
     * @param sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
     * @return amountOut The amount of tokenOut that would be received
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}
