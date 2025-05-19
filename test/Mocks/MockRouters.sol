// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3SwapRouter} from "../../src/Interfaces/IUniswapV3SwapRouter.sol";
import {IPancakeRouter} from "../../src/Interfaces/IPancakeRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouters {
    // Mock implementations of Uniswap V3 and PancakeSwap routers
    MockUniswapV3Router public uniswapV3Router;
    MockPancakeRouter public pancakeRouter;

    constructor() {
        uniswapV3Router = new MockUniswapV3Router();
        pancakeRouter = new MockPancakeRouter();
    }
}
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

            // Calculate output amount
            amounts[i + 1] = (amountInAfterFee * rate) / 1e18;
        }

        // Ensure minimum output is satisfied
        require(amounts[path.length - 1] >= amountOutMin, "Too little received");

        // Transfer final output tokens to recipient
        IERC20(path[path.length - 1]).transfer(to, amounts[path.length - 1]);

        return amounts;
    }
}
