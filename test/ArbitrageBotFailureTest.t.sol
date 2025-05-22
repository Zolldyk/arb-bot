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
import {Test} from "forge-std/Test.sol";

/**
 * @title ArbitrageBotFailureTest
 * @notice Test contract focusing on failure conditions for ArbitrageBot
 * @dev Tests various edge cases and scenarios where the arbitrage should fail
 */
contract ArbitrageBotFailureTest is Test {
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

        // Set up exchange rates (neutral - no arbitrage opportunity)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3000 * 1e6));

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6 * 1e18 / 1e18);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3000 * 1e6));

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3000 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3000 * 1e6));
    }

    /**
     * @notice Test that arbitrage fails when contract is paused
     */
    function testFailure_ContractPaused() public {
        // Toggle the circuit breaker to pause the contract
        vm.prank(owner);
        arbitrageBot.toggleActive();

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage fails when gas price is too high
     */
    function testFailure_GasPriceTooHigh() public {
        // Set max gas price
        vm.prank(owner);
        arbitrageBot.setMaxGasPrice(50 gwei);

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Set tx.gasprice to a high value
        vm.txGasPrice(100 gwei);

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage fails with invalid token pair
     */
    function testFailure_InvalidTokenPair() public {
        // Try with zero address token
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(0), address(mockUSDC), 1 ether, 500, true);

        // Try with same token for both sides
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockWETH), 1 ether, 500, true);
    }

    /**
     * @notice Test that arbitrage fails when there's no profit opportunity
     */
    function testFailure_NoProfitOpportunity() public {
        // Prices are the same on both DEXes, so there's no profit opportunity

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage fails when profit is below threshold
     */
    function testFailure_ProfitBelowThreshold() public {
        // Set up a small price difference that generates some profit, but below threshold
        // Uniswap: 1 WETH = 3005 USDC (0.17% higher than PancakeSwap)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3005 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3005 * 1e6));

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3005 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3005 * 1e6));

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        mockWETH.mint(address(arbitrageBot), loanAmount + flashLoanFee + 0.1 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee + 0.1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + flashLoanFee + 0.1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage fails when unauthorized user tries to execute
     */
    function testFailure_Unauthorized() public {
        // Set up a profitable price difference
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (3050 * 1e6));

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3050 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (3050 * 1e6));

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Try to execute arbitrage as unauthorized user
        vm.expectRevert();
        vm.prank(user); // Not the owner
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test failure when flash loan cannot be repaid
     */
    function testFailure_InsufficientRepayment() public {
        // Set up prices to create a loss instead of profit
        // Uniswap: 1 WETH = 2950 USDC (1.67% lower than PancakeSwap)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 2950 * 1e6 * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), uint256(1e18) / (2950 * 1e6));

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 2950 * 1e6 * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, uint256(1e18) / (2950 * 1e6));

        // Lower the profit threshold temporarily so we can execute the trade
        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(0);

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        uint256 flashLoanFee = loanAmount * 9 / 10000; // 0.09%

        // Only mint enough for the loan but not enough to cover the loss
        mockWETH.mint(address(arbitrageBot), loanAmount);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + flashLoanFee);
        mockWETH.approve(address(mockUniswapRouter), loanAmount);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Try to execute arbitrage
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            true // Uniswap to PancakeSwap - this will create a loss
        );
    }

    /**
     * @notice Test failure when slippage tolerance is too high
     */
    function testFailure_SlippageToleranceTooHigh() public {
        // Try to set a slippage tolerance above the maximum (>10%)
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(1001); // 10.01%
    }

    /**
     * @notice Test failure with flash loan callback from unauthorized sender
     */
    function testFailure_UnauthorizedFlashLoanCallback() public {
        // Prepare flash loan parameters
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockWETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 0.001 ether;

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

        // Try to call receiveFlashLoan directly from an unauthorized sender
        vm.expectRevert();
        vm.prank(user); // Not the Balancer Vault
        arbitrageBot.receiveFlashLoan(tokens, amounts, feeAmounts, userData);
    }

    /**
     * @notice Test failure when token mismatch in flash loan callback
     */
    function testFailure_TokenMismatchInCallback() public {
        // Create a new mock token for testing mismatch
        MockToken mockDAI = new MockToken("Dai Stablecoin", "DAI", 18);

        // Prepare flash loan parameters with token mismatch
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockDAI); // Different from tokenBorrow in params

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 0.001 ether;

        // Encode arbitrage parameters
        bytes memory userData = abi.encode(
            ArbitrageBot.ArbitrageParams({
                tokenBorrow: address(mockWETH), // Mismatch with tokens[0]
                tokenTarget: address(mockUSDC),
                amount: 1 ether,
                uniswapPoolFee: 500,
                uniToPancake: true
            })
        );

        // Mock the Balancer Vault address
        vm.mockCall(
            address(mockBalancerVault), abi.encodeWithSignature("getVault()"), abi.encode(address(mockBalancerVault))
        );

        // Try to call receiveFlashLoan with token mismatch
        vm.expectRevert();
        vm.prank(address(mockBalancerVault)); // Authorized sender
        arbitrageBot.receiveFlashLoan(tokens, amounts, feeAmounts, userData);
    }

    /**
     * @notice Test failure when setting zero address for price feed
     */
    function testFailure_InvalidPriceFeedAddress() public {
        // Try to set price feed with zero token address
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.setPriceFeed(address(0), address(mockWETHFeed));

        // Try to set price feed with zero feed address
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.setPriceFeed(address(mockWETH), address(0));
    }

    /**
     * @notice Test emergency withdrawal when no tokens are present
     */
    function testFailure_EmergencyWithdrawNoTokens() public {
        // Create a new token with zero balance
        MockToken emptyToken = new MockToken("Empty Token", "EMPTY", 18);

        // Try to emergency withdraw when balance is zero
        vm.expectRevert();
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(address(emptyToken));
    }
}
