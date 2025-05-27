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
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6)

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3000 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6)
    }

    /**
     * @notice Test that arbitrage reverts when contract is paused
     */
    function test_RevertWhen_ContractPaused() public {
        // Toggle the circuit breaker to pause the contract
        vm.prank(owner);
        arbitrageBot.toggleActive();

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Expect revert with specific error
        vm.expectRevert(ArbitrageBot.ArbitrageBot__ContractPaused.selector);
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage reverts when gas price is too high
     */
    function test_RevertWhen_GasPriceTooHigh() public {
        // Set max gas price
        vm.prank(owner);
        arbitrageBot.setMaxGasPrice(50 gwei);

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Set tx.gasprice to a high value
        vm.txGasPrice(100 gwei);

        // Expect revert with specific error
        vm.expectRevert(ArbitrageBot.ArbitrageBot__AbnormalPriceDetected.selector);
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage reverts with invalid token pair
     */
    function test_RevertWhen_InvalidTokenPair() public {
        // Try with zero address token
        vm.expectRevert(ArbitrageBot.ArbitrageBot__InvalidTokenPair.selector);
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(0), address(mockUSDC), 1 ether, 500, true);

        // Try with same token for both sides
        vm.expectRevert(ArbitrageBot.ArbitrageBot__InvalidTokenPair.selector);
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockWETH), 1 ether, 500, true);
    }

    /**
     * @notice Test that arbitrage reverts when there's no profit opportunity
     */
    function test_RevertWhen_NoProfitOpportunity() public {
        // Create a scenario where arbitrage results in significant loss
        // Uniswap: 1 WETH = 3000 USDC
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6

        // PancakeSwap: 1 WETH = 2900 USDC (much lower - 3.33% difference)
        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 2900 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 344827586206896552); // 1e18 * 1e6 / (2900 * 1e6)

        // Update quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3000 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6

        // Prepare for arbitrage with NO buffer - only the flash loan amount
        uint256 loanAmount = 1 ether;
        // Don't mint any extra tokens to the arbitrage bot

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount);
        mockWETH.approve(address(mockUniswapRouter), loanAmount);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // This should fail because:
        // 1. Started with 0 ETH in contract
        // 2. Get 1 ETH flash loan
        // 3. Sell 1 ETH on Uniswap → get ~2997 USDC (after 0.05% fee)
        // 4. Buy ETH on PancakeSwap → get ~1.032 ETH worth (but 2997 USDC / 2900 rate = ~1.033 ETH)
        // 5. After PancakeSwap's 0.25% fee: ~1.030 ETH
        // 6. Still have 1 ETH to repay, so small profit of ~0.03 ETH

        // Let's make PancakeSwap worse
        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 2800 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 357142857142857143); // 1e18 * 1e6 / (2800 * 1e6)

        vm.expectRevert(); // Should revert due to insufficient funds for repayment
        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage reverts when profit is below threshold
     */
    function test_RevertWhen_ProfitBelowThreshold() public {
        // The contract will start with 0 ETH and only use the flash loan

        // Set up prices with a small difference that creates minimal profit
        // Uniswap: 3002 USDC (sell high)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3002 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 333000666001332002); // 1e18 * 1e6 / (3002 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3002 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 333000666001332002);

        // PancakeSwap: 3000 USDC (buy low) - from setUp()
        // This creates only 0.067% price difference

        // Expected calculation:
        // 1. Sell 1 ETH on Uniswap: 3002 * (1 - 0.0005) = 3000.499 USDC
        // 2. Buy ETH on PancakeSwap: 3000.499 / 3000 = 1.0001663 ETH * (1 - 0.0025) = 0.99766 ETH
        // 3. Loss: 0.99766 - 1 = -0.00234 ETH (this will fail due to insufficient funds)

        // With a slightly larger spread to get minimal profit
        // Uniswap: 3010 USDC
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3010 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 332225913621262458); // 1e18 * 1e6 / (3010 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3010 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 332225913621262458);

        // PancakeSwap: 2995 USDC (bigger spread of 0.5%)
        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 2995 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 334169449081803005); // 1e18 * 1e6 / (2995 * 1e6)

        // Expected calculation:
        // 1. Sell 1 ETH on Uniswap: 3010 * (1 - 0.0005) = 3008.495 USDC
        // 2. Buy ETH on PancakeSwap: 3008.495 / 2995 = 1.00450 ETH * (1 - 0.0025) = 1.002 ETH
        // 3. Gross profit: 1.002 - 1 = 0.002 ETH = 2e15 wei
        // 4. At $3000/ETH, this is ~$6 profit
        // 5. After gas costs, should be below 10 USDC threshold

        uint256 loanAmount = 1 ether;

        // The contract will get the flash loan and must make it profitable enough to repay + profit
        // We still need to pre-approve for the potential transactions
        vm.startPrank(address(arbitrageBot));

        // Give approval for more than needed
        mockWETH.approve(address(mockBalancerVault), loanAmount * 2);
        mockWETH.approve(address(mockUniswapRouter), loanAmount * 2);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Use high gas price to increase gas costs and reduce net profit
        vm.txGasPrice(100 gwei);

        // Expect revert due to profit below threshold or insufficient funds for repayment
        vm.expectRevert();

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test that arbitrage reverts when unauthorized user tries to execute
     */
    function test_RevertWhen_Unauthorized() public {
        // Set up a profitable price difference
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 332225913621262458); // 1e18 * 1e6 / (3050 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3050 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 332225913621262458); // 1e18 * 1e6 / (3050 * 1e6)

        // Prepare for arbitrage
        uint256 loanAmount = 1 ether;
        mockWETH.mint(address(arbitrageBot), loanAmount * 2);

        // Expect revert due to unauthorized access (Ownable revert)
        vm.expectRevert();
        vm.prank(user); // Not the owner
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test revert when flash loan cannot be repaid
     */
    function test_RevertWhen_InsufficientRepayment() public {
        // Create an extreme loss scenario
        // Uniswap: 1 WETH = 2000 USDC (very low)
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 2000 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 500000000000000000); // 1e18 * 1e6 / (2000 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 2000 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 500000000000000000);

        // PancakeSwap: 4000 USDC per ETH (very high)
        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 4000 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 250000000000000000); // 1e18 * 1e6 / (4000 * 1e6)

        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(0);

        uint256 loanAmount = 1 ether;

        // No initial balance - starting with 0 ETH
        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount);
        mockWETH.approve(address(mockUniswapRouter), loanAmount);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Expected: Sell 1 ETH for 2000 USDC, try to buy ETH at 4000 USDC rate
        // Will get only ~0.5 ETH back, can't repay 1 ETH loan

        vm.expectRevert(); // Should revert due to insufficient funds

        vm.prank(owner);
        arbitrageBot.executeArbitrage(address(mockWETH), address(mockUSDC), loanAmount, 500, true);
    }

    /**
     * @notice Test revert when slippage tolerance is too high
     */
    function test_RevertWhen_SlippageToleranceTooHigh() public {
        // Try to set a slippage tolerance above the maximum (>10%)
        vm.expectRevert(abi.encodeWithSelector(ArbitrageBot.ArbitrageBot__SlippageTooHigh.selector, 1001, 1000));
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(1001); // 10.01%
    }

    /**
     * @notice Test revert with flash loan callback from unauthorized sender
     */
    function test_RevertWhen_UnauthorizedFlashLoanCallback() public {
        // Prepare flash loan parameters
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockWETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 0.001 ether;

        // Encode arbitrage parameters (this struct access might need adjustment)
        bytes memory userData = abi.encode(
            address(mockWETH), // tokenBorrow
            address(mockUSDC), // tokenTarget
            uint256(1 ether), // amount
            uint24(500), // uniswapPoolFee
            bool(true) // uniToPancake
        );

        // Expect revert due to unauthorized sender
        vm.expectRevert(ArbitrageBot.ArbitrageBot__Unauthorized.selector);
        vm.prank(user); // Not the Balancer Vault
        arbitrageBot.receiveFlashLoan(tokens, amounts, feeAmounts, userData);
    }

    /**
     * @notice Test revert when setting invalid price feed addresses
     */
    function test_RevertWhen_InvalidPriceFeedAddress() public {
        // Try to set price feed with zero token address
        vm.expectRevert(ArbitrageBot.ArbitrageBot__InvalidAddress.selector);
        vm.prank(owner);
        arbitrageBot.setPriceFeed(address(0), address(mockWETHFeed));

        // Try to set price feed with zero feed address
        vm.expectRevert(ArbitrageBot.ArbitrageBot__InvalidAddress.selector);
        vm.prank(owner);
        arbitrageBot.setPriceFeed(address(mockWETH), address(0));
    }

    /**
     * @notice Test that emergency withdrawal works when there are tokens
     */
    function test_EmergencyWithdraw_Success() public {
        // Give the contract some tokens
        mockWETH.mint(address(arbitrageBot), 1 ether);

        uint256 initialOwnerBalance = mockWETH.balanceOf(owner);

        // Emergency withdraw should work
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(address(mockWETH));

        uint256 finalOwnerBalance = mockWETH.balanceOf(owner);

        assertEq(finalOwnerBalance, initialOwnerBalance + 1 ether, "Owner should receive withdrawn tokens");
        assertEq(mockWETH.balanceOf(address(arbitrageBot)), 0, "Contract should have zero balance after withdrawal");
    }

    /**
     * @notice Test that emergency withdrawal does nothing when no tokens are present
     */
    function test_EmergencyWithdraw_NoTokens() public {
        // Create a new token with zero balance
        MockToken emptyToken = new MockToken("Empty Token", "EMPTY", 18);

        uint256 initialOwnerBalance = emptyToken.balanceOf(owner);

        // Emergency withdraw should complete without error even with zero balance
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(address(emptyToken));

        uint256 finalOwnerBalance = emptyToken.balanceOf(owner);

        assertEq(finalOwnerBalance, initialOwnerBalance, "Owner balance should remain unchanged");
    }
}
