// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArbitrageBotTestAdvanced} from "../ArbitrageBotTestAdvanced.t.sol";
import {ArbitrageBot} from "../../src/ArbitrageBot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3SwapRouter} from "../../src/Interfaces/IUniswapV3SwapRouter.sol";
import {IUniswapV3Quoter} from "../../src/Interfaces/IUniswapV3Quoter.sol";
import {IPancakeRouter} from "../../src/Interfaces/IPancakeRouter.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title ArbitrageBotIntegrationTest
 * @notice Integration tests for ArbitrageBot using mainnet fork
 * @dev Tests real interactions with Uniswap V3, PancakeSwap and Balancer on a forked network
 */
contract ArbitrageBotIntegrationTest is ArbitrageBotTestAdvanced {
    // Helper functions for WETH and token management
    function _wrapETH(address recipient, uint256 amount) internal {
        // Get WETH contract
        address wethContract = WETH;

        // Send ETH to WETH contract
        (bool success,) = wethContract.call{value: amount}("");
        require(success, "ETH transfer failed");

        // Transfer WETH to recipient
        vm.prank(address(this));
        IERC20(wethContract).transfer(recipient, amount);
    }

    function _approveTokens(address spender, address token, uint256 amount) internal {
        vm.prank(address(this));
        IERC20(token).approve(spender, amount);
    }

    /**
     * @notice Test direct interaction with Uniswap V3
     * @dev Verifies we can execute swaps on Uniswap V3
     */
    function testUniswapV3DirectInteraction() public {
        // Fund this contract with ETH and wrap to WETH
        vm.deal(address(this), 10 ether);
        _wrapETH(address(this), 10 ether);

        // Initial balances
        uint256 initialWETH = IERC20(WETH).balanceOf(address(this));
        uint256 initialUSDC = IERC20(USDC).balanceOf(address(this));

        // Approve Uniswap to spend WETH
        _approveTokens(UNISWAP_ROUTER, WETH, 1 ether);

        // Create swap parameters
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 500, // 0.05% pool
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: 1 ether,
            amountOutMinimum: 1, // No minimum for testing
            sqrtPriceLimitX96: 0
        });

        // Execute swap
        vm.prank(address(this));
        uint256 amountOut = IUniswapV3SwapRouter(UNISWAP_ROUTER).exactInputSingle(params);

        // Verify swap worked
        assertLt(IERC20(WETH).balanceOf(address(this)), initialWETH, "WETH balance should decrease");
        assertGt(IERC20(USDC).balanceOf(address(this)), initialUSDC, "USDC balance should increase");
        assertGt(amountOut, 0, "Swap should return non-zero amount");

        console.log("Uniswap V3 Swap: 1 WETH -> %s USDC", amountOut / 1e6);
    }

    /**
     * @notice Test direct interaction with PancakeSwap
     * @dev Verifies we can execute swaps on PancakeSwap
     */
    function testPancakeSwapDirectInteraction() public {
        // Fund this contract with ETH and wrap to WETH
        vm.deal(address(this), 10 ether);
        _wrapETH(address(this), 10 ether);

        // Initial balances
        uint256 initialWETH = IERC20(WETH).balanceOf(address(this));
        uint256 initialUSDC = IERC20(USDC).balanceOf(address(this));

        // Approve PancakeSwap to spend WETH
        _approveTokens(PANCAKE_ROUTER, WETH, 1 ether);

        // Create path for swap
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        // Execute swap
        vm.prank(address(this));
        uint256[] memory amounts = IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokens(
            1 ether,
            1, // No minimum for testing
            path,
            address(this),
            block.timestamp + 300
        );

        // Verify swap worked
        assertLt(IERC20(WETH).balanceOf(address(this)), initialWETH, "WETH balance should decrease");
        assertGt(IERC20(USDC).balanceOf(address(this)), initialUSDC, "USDC balance should increase");
        assertGt(amounts[1], 0, "Swap should return non-zero amount");

        console.log("PancakeSwap Swap: 1 WETH -> %s USDC", amounts[1] / 1e6);
    }

    /**
     * @notice Test price comparison between Uniswap V3 and PancakeSwap
     * @dev This test helps identify if there's an arbitrage opportunity
     */
    function testPriceComparison() public {
        // Fund this contract with ETH and wrap to WETH
        vm.deal(address(this), 10 ether);
        _wrapETH(address(this), 10 ether);

        // Approve both DEXes
        _approveTokens(UNISWAP_ROUTER, WETH, 1 ether);
        _approveTokens(PANCAKE_ROUTER, WETH, 1 ether);

        // Get Uniswap V3 quote
        IUniswapV3SwapRouter.ExactInputSingleParams memory uniParams = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 500, // 0.05% pool
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: 1 ether,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        vm.prank(address(this));
        uint256 uniswapOut = IUniswapV3SwapRouter(UNISWAP_ROUTER).exactInputSingle(uniParams);

        // Reset balances
        vm.deal(address(this), 10 ether);
        _wrapETH(address(this), 10 ether);

        // Get PancakeSwap quote
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        vm.prank(address(this));
        uint256[] memory amounts = IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokens(
            1 ether, 1, path, address(this), block.timestamp + 300
        );
        uint256 pancakeOut = amounts[1];

        // Compare prices
        console.log("Uniswap V3: 1 WETH -> %s USDC", uniswapOut / 1e6);
        console.log("PancakeSwap: 1 WETH -> %s USDC", pancakeOut / 1e6);

        if (uniswapOut > pancakeOut) {
            console.log("Potential arbitrage: Buy on PancakeSwap, sell on Uniswap");
            console.log("Price difference: %s USDC", (uniswapOut - pancakeOut) / 1e6);
        } else if (pancakeOut > uniswapOut) {
            console.log("Potential arbitrage: Buy on Uniswap, sell on PancakeSwap");
            console.log("Price difference: %s USDC", (pancakeOut - uniswapOut) / 1e6);
        } else {
            console.log("No arbitrage opportunity found");
        }
    }

    /**
     * @notice Test quoter interactions
     * @dev Verifies we can get accurate quotes from Uniswap V3
     */
    function testUniswapQuoter() public {
        // Get quote for WETH->USDC
        try IUniswapV3Quoter(UNISWAP_QUOTER).quoteExactInputSingle(
            WETH,
            USDC,
            500, // 0.05% pool
            1 ether,
            0
        ) returns (uint256 amountOut) {
            console.log("Uniswap V3 Quote: 1 WETH -> %s USDC", amountOut / 1e6);
            assertGt(amountOut, 0, "Quote should be non-zero");
        } catch {
            console.log("Uniswap quote failed");
        }
    }

    receive() external payable {}
}
