// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3SwapRouter} from "../../src/Interfaces/IUniswapV3SwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockUniswapV3Router
 * @notice Mock implementation of Uniswap V3 Router for testing
 * @dev Simulates Uniswap V3 swaps with configurable exchange rates
 */
contract MockUniswapV3Router {
    // Exchange rates for token pairs (tokenIn => tokenOut => rate)
    // Rate is scaled by 1e18 (e.g., 1.05e18 means 1 tokenIn = 1.05 tokenOut)
    mapping(address => mapping(address => uint256)) public exchangeRates;

    // Set exchange rate for a token pair
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
    }

    // Uniswap V3 exactInputSingle function
    function exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        // Transfer input tokens from sender to this contract
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Calculate output amount based on exchange rate
        uint256 rate = exchangeRates[params.tokenIn][params.tokenOut];
        require(rate > 0, "Exchange rate not set");

        // Apply fee (simulate pool fee)
        uint256 feeAmount;
        if (params.fee == 500) {
            // 0.05%
            feeAmount = params.amountIn * 5 / 10000;
        } else if (params.fee == 3000) {
            // 0.3%
            feeAmount = params.amountIn * 30 / 10000;
        } else if (params.fee == 10000) {
            // 1%
            feeAmount = params.amountIn * 100 / 10000;
        } else {
            revert("Unsupported fee tier");
        }

        uint256 amountInAfterFee = params.amountIn - feeAmount;
        amountOut = (amountInAfterFee * rate) / 1e18;

        // Ensure minimum output is satisfied
        require(amountOut >= params.amountOutMinimum, "Too little received");

        // Transfer output tokens to recipient
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }
}
