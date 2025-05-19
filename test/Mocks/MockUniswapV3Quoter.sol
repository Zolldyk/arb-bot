// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3Quoter} from "../../src/Interfaces/IUniswapV3Quoter.sol";

/**
 * @title MockUniswapV3Quoter
 * @notice Mock implementation of Uniswap V3 Quoter for testing
 * @dev Implements the IUniswapV3Quoter interface with configurable quotes
 */
contract MockUniswapV3Quoter is IUniswapV3Quoter {
    // Quotes for token pairs (tokenIn => tokenOut => fee => rate)
    // Rate is scaled by 1e18 (e.g., 1.05e18 means 1 tokenIn = 1.05 tokenOut)
    mapping(address => mapping(address => mapping(uint24 => uint256))) public quotes;

    /**
     * @notice Set quote for a token pair and fee tier
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Fee tier
     * @param rate Exchange rate (scaled by 1e18)
     */
    function setQuote(address tokenIn, address tokenOut, uint24 fee, uint256 rate) external {
        quotes[tokenIn][tokenOut][fee] = rate;
    }

    /**
     * @notice Returns the amount out received for a given exact input swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Fee tier
     * @param amountIn Input amount
     * @param sqrtPriceLimitX96 Price limit (ignored in mock)
     * @return amountOut Output amount based on configured rate
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external view override returns (uint256 amountOut) {
        // Get the configured rate for this token pair and fee
        uint256 rate = quotes[tokenIn][tokenOut][fee];
        require(rate > 0, "Quote not set");

        // Apply fee reduction
        uint256 feeAmount;
        if (fee == 500) {
            // 0.05%
            feeAmount = amountIn * 5 / 10000;
        } else if (fee == 3000) {
            // 0.3%
            feeAmount = amountIn * 30 / 10000;
        } else if (fee == 10000) {
            // 1%
            feeAmount = amountIn * 100 / 10000;
        } else {
            revert("Unsupported fee tier");
        }

        uint256 amountInAfterFee = amountIn - feeAmount;

        // Calculate output amount based on rate
        return (amountInAfterFee * rate) / 1e18;
    }
}
