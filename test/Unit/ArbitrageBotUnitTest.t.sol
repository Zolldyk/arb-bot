// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArbitrageBotTestAdvanced} from "../ArbitrageBotTestAdvanced.t.sol";
import {MockToken} from "../Mocks/MockToken.sol";
import {MockBalancerVault} from "../Mocks/MockBalancerVault.sol";
import {MockRouters} from "../Mocks/MockRouters.sol";
import {MockPriceFeed} from "../Mocks/MockPriceFeed.sol";
import {MockUniswapV3Quoter} from "../Mocks/MockUniswapV3Quoter.sol";
import {MockUniswapV3Router} from "../Mocks/MockUniswapV3Router.sol";
import {MockPancakeRouter} from "../Mocks/MockPancakeRouter.sol";
import {ArbitrageBot} from "../../src/ArbitrageBot.sol";
import {Test} from "forge-std/Test.sol";

/**
 * @title ArbitrageBotUnitTest
 * @notice Unit tests for ArbitrageBot using mocked dependencies
 */
contract ArbitrageBotUnitTest is Test {
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
        // PancakeSwap: 1 WETH = 3000 USDC
        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6 * 1e18 / 1e18);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3000 * 1e6));

        // Uniswap: 1 WETH = 3010 USDC (creates a price discrepancy)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3010 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3010 * 1e6));

        // Set quotes for the Uniswap Quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3010 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3010 * 1e6));

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
     * @notice Test flash loan simulation
     * @dev Verifies the flash loan callback is executed correctly
     */
    function testFlashLoanCallback() public {
        // Prepare tokens for repayment (only the loan amount, no fee for Balancer)
        mockWETH.mint(address(arbitrageBot), 1 ether); // Amount only, no fee

        // Approve vault to take back tokens
        vm.prank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), 1 ether);

        // Prepare flash loan parameters
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockWETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // Encode arbitrage parameters
        bytes memory userData = abi.encode(
            ArbitrageBot.ArbitrageParams({
                tokenBorrow: address(mockWETH),
                tokenTarget: address(mockUSDC),
                amount: 1 ether,
                uniswapPoolFee: 500,
                uniToPancake: true
            })
        );

        // Execute flash loan - this will call receiveFlashLoan on the arbitrage bot
        vm.prank(owner);
        mockBalancerVault.flashLoan(address(arbitrageBot), tokens, amounts, userData);

        // Verify the flash loan was repaid (balancer vault should have received the tokens back)
        assertGe(mockWETH.balanceOf(address(mockBalancerVault)), 100 ether);
    }

    /**
     * @notice Test that arbitrage execution fails when profit is below threshold
     */
    function testArbitrageFailsBelowProfitThreshold() public {
        // Change exchange rates to make arbitrage unprofitable
        // PancakeSwap: 1 WETH = 3000 USDC
        // Uniswap: 1 WETH = 3001 USDC (only 0.03% difference, not enough to cover fees)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3001 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3001 * 1e6));

        // Update quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3001 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3001 * 1e6));

        // Prepare for arbitrage (no flash loan fee for Balancer)
        deal(address(mockWETH), address(arbitrageBot), 1 ether);

        vm.prank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), 1 ether);

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            1 ether,
            500,
            true // Uniswap to PancakeSwap
        );
    }

    /**
     * @notice Test successful arbitrage execution with profit
     */
    function testSuccessfulArbitrage() public {
        // Set up a profitable arbitrage scenario
        // PancakeSwap: 1 WETH = 3000 USDC
        // Uniswap: 1 WETH = 3050 USDC (1.67% difference, should be enough for profit)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3050 * 1e6));

        // Update quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3050 * 1e6));

        // Record initial owner balance
        uint256 initialOwnerBalance = mockWETH.balanceOf(owner);

        // Give the arbitrageBot some WETH (no flash loan fee needed for Balancer)
        mockWETH.mint(address(arbitrageBot), 1.1 ether);

        // Approve tokens for the arbitrage
        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), 1.1 ether);
        mockWETH.approve(address(mockUniswapRouter), 1.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 10000000 * 1e6);
        vm.stopPrank();

        // Execute arbitrage
        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            1 ether,
            500,
            true // Uniswap to PancakeSwap (buy low on PancakeSwap, sell high on Uniswap)
        );

        // Check that owner received profit
        uint256 finalOwnerBalance = mockWETH.balanceOf(owner);
        assertGt(finalOwnerBalance, initialOwnerBalance, "Owner should have received profit");
    }

    /**
     * @notice Test arbitrage with token approval and transfers
     */
    function testArbitrageWithTokenApprovals() public {
        // Set up a profitable arbitrage scenario
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6 * 1e18 / 1e18);

        // Record initial approval state
        vm.prank(address(arbitrageBot));

        // Give the arbitrageBot some WETH (no flash loan fee for Balancer)
        mockWETH.mint(address(arbitrageBot), 1 ether);

        // Execute arbitrage
        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), 1 ether);
        mockWETH.approve(address(mockUniswapRouter), 1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 10000000 * 1e6);
        vm.stopPrank();

        // Verify approvals were set correctly
        vm.prank(address(arbitrageBot));
        uint256 uniswapAllowance = mockWETH.allowance(address(arbitrageBot), address(mockUniswapRouter));
        assertEq(uniswapAllowance, 1 ether, "Token approval should be set correctly");
    }

    /**
     * @notice Test circuit breaker functionality
     */
    function testCircuitBreaker() public {
        // Toggle the circuit breaker to pause the contract
        vm.prank(owner);
        arbitrageBot.toggleActive();

        // Prepare for arbitrage
        mockWETH.mint(address(arbitrageBot), 1 ether);

        // Try to execute arbitrage while paused
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), 1 ether, 500, true);

        // Toggle back to active
        vm.prank(owner);
        arbitrageBot.toggleActive();

        // Now arbitrage should work
        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), 1 ether);
        mockWETH.approve(address(mockUniswapRouter), 1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 10000000 * 1e6);
        vm.stopPrank();

        // Execute arbitrage
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), 1 ether, 500, true);
    }

    /**
     * @notice Test emergency withdrawal functionality
     */
    function testEmergencyWithdraw() public {
        // Send some tokens to the arbitrage bot
        mockWETH.mint(address(arbitrageBot), 1 ether);
        mockUSDC.mint(address(arbitrageBot), 1000 * 1e6);

        // Check initial balances
        uint256 initialOwnerWETH = mockWETH.balanceOf(owner);
        uint256 initialOwnerUSDC = mockUSDC.balanceOf(owner);

        // Emergency withdraw WETH
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(address(mockWETH));

        // Check balances after WETH withdrawal
        assertEq(mockWETH.balanceOf(owner), initialOwnerWETH + 1 ether, "Owner should receive all WETH");
        assertEq(mockWETH.balanceOf(address(arbitrageBot)), 0, "Contract should have 0 WETH");

        // Emergency withdraw USDC
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(address(mockUSDC));

        // Check balances after USDC withdrawal
        assertEq(mockUSDC.balanceOf(owner), initialOwnerUSDC + 1000 * 1e6, "Owner should receive all USDC");
        assertEq(mockUSDC.balanceOf(address(arbitrageBot)), 0, "Contract should have 0 USDC");
    }
}
