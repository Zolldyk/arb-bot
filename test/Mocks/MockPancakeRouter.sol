// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPancakeRouter} from "../../src/Interfaces/IPancakeRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockPancakeRouter
 * @notice Mock implementation of PancakeSwap Router for testing
 * @dev Simulates PancakeSwap swaps with configurable exchange rates
 */
contract MockPancakeRouter {
    // Exchange rates for token pairs (tokenIn => tokenOut => rate)
    // Rate is scaled by 1e18 (e.g., 1.05e18 means 1 tokenIn = 1.05 tokenOut)
    mapping(address => mapping(address => uint256)) public exchangeRates;

    // Fee percentage (0.25% = 25 / 10000)
    uint256 public constant FEE_PERCENTAGE = 25;

    // Set exchange rate for a token pair
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
    }

    // PancakeSwap swapExactTokensForTokens function
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(deadline >= block.timestamp, "Expired");

        // Initialize amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Transfer input tokens from sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Calculate output amounts for each hop in the path
        for (uint256 i = 0; i < path.length - 1; i++) {
            address tokenIn = path[i];
            address tokenOut = path[i + 1];

            // Get exchange rate
            uint256 rate = exchangeRates[tokenIn][tokenOut];
            require(rate > 0, "Exchange rate not set");

            // Apply fee
            uint256 feeAmount = (amounts[i] * FEE_PERCENTAGE) / 10000;
            uint256 amountInAfterFee = amounts[i] - feeAmount;

            // Calculate output amount with proper decimal handling
            // The rate should already account for decimal differences
            amounts[i + 1] = (amountInAfterFee * rate) / 1e18;
        }

        // Ensure minimum output is satisfied
        require(amounts[path.length - 1] >= amountOutMin, "Too little received");

        // Transfer final output tokens to recipient
        IERC20(path[path.length - 1]).transfer(to, amounts[path.length - 1]);

        return amounts;
    }
}
