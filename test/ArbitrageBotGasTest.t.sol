// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArbitrageBotTestAdvanced} from "./ArbitrageBotTestAdvanced.t.sol";
import {MockToken} from "./Mocks/MockToken.sol";
import {MockBalancerVault} from "./Mocks/MockBalancerVault.sol";
import {MockRouters} from "./Mocks/MockRouters.sol";
import {MockPriceFeed} from "./Mocks/MockPriceFeed.sol";
import {MockUniswapV3Quoter} from "./Mocks/MockUniswapV3Quoter.sol";
import {MockUniswapV3Router} from "./Mocks/MockUniswapV3Router.sol";
import {MockPancakeRouter} from "./Mocks/MockPancakeRouter.sol";
import {ArbitrageBot} from "../src/ArbitrageBot.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title ArbitrageBotGasTest
 * @notice Gas tests for ArbitrageBot to measure and optimize gas usage
 * @dev Carefully measures gas consumption of main contract operations
 */
contract ArbitrageBotGasTest is Test {
    // Contract to test
    ArbitrageBot public arbitrageBot;

    // Mock contracts
    MockBalancerVault public mockBalancerVault;
    MockUniswapV3Router public mockUniswapRouter;
    MockPancakeRouter public mockPancakeRouter;
    MockUniswapV3Quoter public mockUniswapQuoter;

    // Mock tokens
    MockToken public mockWETH;
    MockToken public mockUSDC;

    // Mock price feeds
    MockPriceFeed public mockWETHFeed;
    MockPriceFeed public mockUSDCFeed;

    // Test accounts
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    // Constants
    uint256 constant MIN_PROFIT_THRESHOLD = 10 * 1e6; // 10 USDC

    function setUp() public {
        // Deploy mock tokens
        mockWETH = new MockToken("Wrapped Ether", "WETH", 18);
        mockUSDC = new MockToken("USD Coin", "USDC", 6);

        // Deploy mock price feeds
        mockWETHFeed = new MockPriceFeed(3000 * 1e8, 8, "ETH / USD"); // $3000 per ETH
        mockUSDCFeed = new MockPriceFeed(1 * 1e8, 8, "USDC / USD"); // $1 per USDC

        // Deploy mock contracts
        mockBalancerVault = new MockBalancerVault();
        mockUniswapRouter = new MockUniswapV3Router();
        mockPancakeRouter = new MockPancakeRouter();
        mockUniswapQuoter = new MockUniswapV3Quoter();

        // Set exchange rates
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3050 * 1e6));

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6 * 1e18 / 1e18);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3000 * 1e6));

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3050 * 1e6));

        // Deploy arbitrage bot with mocked dependencies
        vm.startPrank(owner);
        arbitrageBot = new ArbitrageBot(
            address(mockBalancerVault),
            address(mockUniswapRouter),
            address(mockPancakeRouter),
            address(mockUniswapQuoter),
            MIN_PROFIT_THRESHOLD
        );

        // Set price feeds
        arbitrageBot.setPriceFeed(address(mockWETH), address(mockWETHFeed));
        arbitrageBot.setPriceFeed(address(mockUSDC), address(mockUSDCFeed));

        // Set preferred pool fees
        arbitrageBot.setPreferredUniswapPoolFee(address(mockWETH), address(mockUSDC), 500); // 0.05%

        vm.stopPrank();

        // Mint tokens to mock contracts for testing
        mockWETH.mint(address(mockBalancerVault), 100 ether);
        mockUSDC.mint(address(mockUniswapRouter), 1_000_000 * 1e6);
        mockUSDC.mint(address(mockPancakeRouter), 1_000_000 * 1e6);
        mockWETH.mint(address(mockUniswapRouter), 100 ether);
        mockWETH.mint(address(mockPancakeRouter), 100 ether);
    }

    /**
     * @notice Measure gas usage of the executeArbitrage function
     */
    function testGas_ExecuteArbitrage() public {
        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Measure gas usage
        uint256 startGas = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            true // Uniswap to PancakeSwap
        );

        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for executeArbitrage: %s", gasUsed);
    }

    /**
     * @notice Compare gas usage between different arbitrage directions
     */
    function testGas_ArbitrageDirections() public {
        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        mockWETH.mint(address(arbitrageBot), (loanAmount + flashLoanFee + 0.1 ether) * 2); // For 2 tests

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), (loanAmount + flashLoanFee + 0.1 ether) * 2);
        mockWETH.approve(address(mockUniswapRouter), (loanAmount + flashLoanFee + 0.1 ether) * 2);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Test Uniswap to PancakeSwap
        uint256 startGas1 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            true // Uniswap to PancakeSwap
        );

        uint256 gasUsed1 = startGas1 - gasleft();
        console.log("Gas used (Uniswap to PancakeSwap): %s", gasUsed1);

        // Test PancakeSwap to Uniswap
        uint256 startGas2 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            false // PancakeSwap to Uniswap
        );

        uint256 gasUsed2 = startGas2 - gasleft();
        console.log("Gas used (PancakeSwap to Uniswap): %s", gasUsed2);

        // Compare gas usage
        console.log("Gas difference: %s", gasUsed1 > gasUsed2 ? gasUsed1 - gasUsed2 : gasUsed2 - gasUsed1);
    }

    /**
     * @notice Measure gas usage with different flash loan amounts
     */
    function testGas_FlashLoanAmounts() public {
        // Test multiple loan amounts
        uint256[] memory loanAmounts = new uint256[](3);
        loanAmounts[0] = 0.1 ether; // Small loan
        loanAmounts[1] = 1 ether; // Medium loan
        loanAmounts[2] = 10 ether; // Large loan

        for (uint256 i = 0; i < loanAmounts.length; i++) {
            uint256 loanAmount = loanAmounts[i];
            uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

            // Prepare for arbitrage
            mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

            vm.startPrank(address(arbitrageBot));
            mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
            mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
            mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
            vm.stopPrank();

            // Measure gas usage
            uint256 startGas = gasleft();

            vm.prank(owner);
            arbitrageBot.executeArbitrage(
                address(mockWETH),
                address(mockUSDC),
                loanAmount,
                500,
                true // Uniswap to PancakeSwap
            );

            uint256 gasUsed = startGas - gasleft();
            console.log("Gas used for loan amount %s ETH: %s", loanAmount / 1e18, gasUsed);
        }
    }

    /**
     * @notice Measure gas usage for different Uniswap fee tiers
     */
    function testGas_FeeTiers() public {
        // Test multiple fee tiers
        uint24[] memory feeTiers = new uint24[](3);
        feeTiers[0] = 500; // 0.05% fee
        feeTiers[1] = 3000; // 0.3% fee
        feeTiers[2] = 10000; // 1% fee

        // Set up exchange rates for all fee tiers
        for (uint256 i = 0; i < feeTiers.length; i++) {
            mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), feeTiers[i], 3050 * 1e6 * 1e18 / 1e18);
            mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), feeTiers[i], uint256(1e18) / (3050 * 1e6));
        }

        for (uint256 i = 0; i < feeTiers.length; i++) {
            // Set preferred pool fee
            vm.prank(owner);
            arbitrageBot.setPreferredUniswapPoolFee(address(mockWETH), address(mockUSDC), feeTiers[i]);

            // Prepare for arbitrage
            uint256 loanAmount = 1 ether;
            uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

            mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

            vm.startPrank(address(arbitrageBot));
            mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
            mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
            mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
            vm.stopPrank();

            // Measure gas usage
            uint256 startGas = gasleft();

            vm.prank(owner);
            arbitrageBot.executeArbitrage(
                address(mockWETH),
                address(mockUSDC),
                loanAmount,
                feeTiers[i],
                true // Uniswap to PancakeSwap
            );

            uint256 gasUsed = startGas - gasleft();
            console.log("Gas used for fee tier %s: %s", feeTiers[i], gasUsed);
        }
    }

    /**
     * @notice Measure gas usage with and without price feeds
     */
    function testGas_WithAndWithoutPriceFeeds() public {
        // Test with price feeds (already set up in setUp)
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Measure gas usage with price feeds
        uint256 startGas1 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);

        uint256 gasUsed1 = startGas1 - gasleft();
        console.log("Gas used with price feeds: %s", gasUsed1);

        // Remove price feeds
        vm.startPrank(owner);
        arbitrageBot.setPriceFeed(address(mockWETH), address(0));
        arbitrageBot.setPriceFeed(address(mockUSDC), address(0));
        vm.stopPrank();

        // Prepare for second test
        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Measure gas usage without price feeds
        uint256 startGas2 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);

        uint256 gasUsed2 = startGas2 - gasleft();
        console.log("Gas used without price feeds: %s", gasUsed2);

        // Compare gas usage
        if (gasUsed1 > gasUsed2) {
            console.log("Using price feeds costs %s more gas", gasUsed1 - gasUsed2);
        } else {
            console.log("Using price feeds saves %s gas", gasUsed2 - gasUsed1);
        }
    }

    /**
     * @notice Measure gas usage of admin functions
     */
    function testGas_AdminFunctions() public {
        uint256 startGas;
        uint256 gasUsed;

        // Measure setMinProfitThreshold
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(20 * 1e6);
        gasUsed = startGas - gasleft();
        console.log("Gas used for setMinProfitThreshold: %s", gasUsed);

        // Measure setSlippageTolerance
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(100);
        gasUsed = startGas - gasleft();
        console.log("Gas used for setSlippageTolerance: %s", gasUsed);

        // Measure setMaxGasPrice
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.setMaxGasPrice(150 gwei);
        gasUsed = startGas - gasleft();
        console.log("Gas used for setMaxGasPrice: %s", gasUsed);

        // Measure toggleActive
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.toggleActive();
        gasUsed = startGas - gasleft();
        console.log("Gas used for toggleActive: %s", gasUsed);

        // Measure setPriceFeed
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.setPriceFeed(address(mockWETH), address(mockWETHFeed));
        gasUsed = startGas - gasleft();
        console.log("Gas used for setPriceFeed: %s", gasUsed);

        // Measure setPreferredUniswapPoolFee
        startGas = gasleft();
        vm.prank(owner);
        arbitrageBot.setPreferredUniswapPoolFee(address(mockWETH), address(mockUSDC), 3000);
        gasUsed = startGas - gasleft();
        console.log("Gas used for setPreferredUniswapPoolFee: %s", gasUsed);
    }

    /**
     * @notice Measure gas usage with high slippage tolerance vs low slippage tolerance
     */
    function testGas_SlippageTolerance() public {
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        // Test with low slippage (0.1%)
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(10);

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        uint256 startGas1 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);

        uint256 gasUsed1 = startGas1 - gasleft();
        console.log("Gas used with 0.1% slippage: %s", gasUsed1);

        // Test with high slippage (1%)
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(100);

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        uint256 startGas2 = gasleft();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);

        uint256 gasUsed2 = startGas2 - gasleft();
        console.log("Gas used with 1% slippage: %s", gasUsed2);

        // Compare gas usage
        console.log("Gas difference: %s", gasUsed1 > gasUsed2 ? gasUsed1 - gasUsed2 : gasUsed2 - gasUsed1);
    }
}
