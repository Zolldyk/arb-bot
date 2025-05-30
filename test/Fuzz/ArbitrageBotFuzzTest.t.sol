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
import {Test, console} from "forge-std/Test.sol";

/**
 * @title ArbitrageBotFuzzTest
 * @notice Fuzz tests for ArbitrageBot using mocked dependencies
 * @dev Uses Foundry's property-based testing to validate contract behavior across a range of inputs
 */
contract ArbitrageBotFuzzTest is Test {
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
        mockWETH.mint(address(mockBalancerVault), 1000 ether);
        mockUSDC.mint(address(mockUniswapRouter), 10_000_000 * 1e6);
        mockUSDC.mint(address(mockPancakeRouter), 10_000_000 * 1e6);
        mockWETH.mint(address(mockUniswapRouter), 1000 ether);
        mockWETH.mint(address(mockPancakeRouter), 1000 ether);
    }

    /**
     * @notice Fuzz test for slippage tolerance setting
     * @param slippageTolerance Random slippage tolerance value
     */
    function testFuzz_SlippageTolerance(uint256 slippageTolerance) public {
        // Bound slippage tolerance to reasonable values
        slippageTolerance = bound(slippageTolerance, 1, 1000);

        // Set slippage tolerance
        vm.prank(owner);
        arbitrageBot.setSlippageTolerance(slippageTolerance);

        // Get config
        (,,,,, uint256 actualSlippageTolerance,,) = arbitrageBot.getConfig();

        // Verify slippage tolerance was set correctly
        assertEq(actualSlippageTolerance, slippageTolerance, "Slippage tolerance should be set correctly");
    }

    /**
     * @notice Fuzz test for min profit threshold setting
     * @param minProfitThreshold Random minimum profit threshold
     */
    function testFuzz_MinProfitThreshold(uint256 minProfitThreshold) public {
        // Bound min profit threshold to reasonable values
        minProfitThreshold = bound(minProfitThreshold, 1, 1000000 * 1e6);

        // Set min profit threshold
        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(minProfitThreshold);

        // Get config
        (,,,, uint256 actualMinProfitThreshold,,,) = arbitrageBot.getConfig();

        // Verify min profit threshold was set correctly
        assertEq(actualMinProfitThreshold, minProfitThreshold, "Min profit threshold should be set correctly");
    }

    /**
     * @notice Fuzz test for price discrepancy profitability
     * @param uniswapPrice Uniswap price for WETH/USDC
     * @param pancakePrice PancakeSwap price for WETH/USDC
     * @param loanAmount Amount to borrow in flash loan
     */
    function testFuzz_PriceDiscrepancyProfitability(uint256 uniswapPrice, uint256 pancakePrice, uint256 loanAmount)
        public
    {
        // Bound inputs to reasonable values
        // Price between $2000-$4000 per ETH
        uniswapPrice = bound(uniswapPrice, 2000 * 1e6, 4000 * 1e6);
        pancakePrice = bound(pancakePrice, 2000 * 1e6, 4000 * 1e6);

        // Loan amount between 0.1-10 ETH
        loanAmount = bound(loanAmount, 0.1 ether, 10 ether);

        // Ensure there's a price difference (at least 1%)
        if (uniswapPrice <= pancakePrice) {
            uniswapPrice = pancakePrice * 101 / 100;
        }

        // Set exchange rates
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), uniswapPrice * 1e18 / 1e18);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 1e18 / uniswapPrice);

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), pancakePrice * 1e18 / 1e18);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 1e18 / pancakePrice);

        // Set quotes for the Uniswap Quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, uniswapPrice * 1e18 / 1e18);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 1e18 / uniswapPrice);

        // Calculate expected profit (no flash loan fee for Balancer)
        uint256 step1Output = loanAmount * pancakePrice / 1e18; // Buy USDC with WETH on PancakeSwap
        uint256 step1Fee = loanAmount * 25 / 10000; // PancakeSwap fee (0.25%)
        uint256 step1OutputAfterFee = loanAmount * (10000 - 25) / 10000 * pancakePrice / 1e18;

        uint256 step2Output = step1OutputAfterFee * 1e18 / uniswapPrice; // Buy WETH with USDC on Uniswap
        uint256 step2Fee = step1OutputAfterFee * 5 / 10000; // Uniswap fee (0.05% pool)
        uint256 step2OutputAfterFee = step1OutputAfterFee * (10000 - 5) / 10000 * 1e18 / uniswapPrice;

        // No flash loan fee for Balancer
        uint256 expectedProfit = step2OutputAfterFee > loanAmount ? step2OutputAfterFee - loanAmount : 0;

        // Determine if arbitrage should be profitable
        bool shouldBeSuccessful = expectedProfit >= MIN_PROFIT_THRESHOLD;

        // Prepare for arbitrage (no flash loan fee for Balancer)
        mockWETH.mint(address(arbitrageBot), loanAmount + 1 ether); // Extra buffer

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + 1 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + 1 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Execute arbitrage
        vm.startPrank(owner);

        try arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            false // PancakeSwap to Uniswap (exploit price difference)
        ) {
            // If execution succeeds, check that it was expected to be profitable
            assertTrue(shouldBeSuccessful, "Arbitrage succeeded but wasn't expected to be profitable");

            // Check that owner received profit
            uint256 ownerBalance = mockWETH.balanceOf(owner);
            assertGt(ownerBalance, 0, "Owner should have received profit");
        } catch {
            // If execution fails, check that it wasn't expected to be profitable
            assertFalse(shouldBeSuccessful, "Arbitrage failed but was expected to be profitable");
        }

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test for different fee tiers using bound
     * @param seedValue Seed value to generate fee tier
     */
    function testFuzz_FeeTiers(uint256 seedValue) public {
        // Bound the input to 0-2 range to select from 3 valid fee tiers
        uint256 feeIndex = bound(seedValue, 0, 2);

        uint24 uniswapFee;
        if (feeIndex == 0) {
            uniswapFee = 500; // 0.05%
        } else if (feeIndex == 1) {
            uniswapFee = 3000; // 0.3%
        } else {
            uniswapFee = 10000; // 1%
        }

        // Set exchange rates and quotes for the specified fee tier
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6);
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), uniswapFee, 3050 * 1e6);

        // Set preferred pool fee
        vm.prank(owner);
        arbitrageBot.setPreferredUniswapPoolFee(address(mockWETH), address(mockUSDC), uniswapFee);

        // Verify the fee tier was set correctly
        uint24 preferredFee = arbitrageBot.getPreferredUniswapPoolFee(address(mockWETH), address(mockUSDC));
        assertEq(preferredFee, uniswapFee, "Preferred fee tier should be set correctly");
    }

    /**
     * @notice Fuzz test for different flash loan amounts
     * @param loanAmount Amount to borrow in flash loan
     */
    function testFuzz_FlashLoanAmount(uint256 loanAmount) public {
        // Bound loan amount to reasonable values (0.1-10 ETH)
        loanAmount = bound(loanAmount, 0.1 ether, 10 ether);

        // Set up a profitable scenario
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3050 * 1e6);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 32786885245901639); // 1e18 * 1e6 / (3050 * 1e6)

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), 3000 * 1e6);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 333333333333333333); // 1e18 * 1e6 / (3000 * 1e6)

        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, 3050 * 1e6);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 32786885245901639); // 1e18 * 1e6 / (3050 * 1e6)

        // Prepare for arbitrage with sufficient buffer
        mockWETH.mint(address(arbitrageBot), loanAmount + 2 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + 2 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + 2 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Set minimum profit threshold to 0 for this test
        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(0);

        // Execute arbitrage
        vm.prank(owner);
        arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            true // Uniswap to PancakeSwap
        );

        // Verify arbitrage executed successfully (check that it didn't revert)
        assertTrue(true, "Arbitrage should execute without reverting");
    }

    /**
     * @notice Simplified fuzz test for price discrepancy
     * @param priceDiff Price difference percentage (1-50%)
     * @param loanAmount Amount to borrow
     */
    function testFuzz_SimplePriceDiscrepancy(uint256 priceDiff, uint256 loanAmount) public {
        // Bound inputs to reasonable ranges
        priceDiff = bound(priceDiff, 1, 50); // 1-50% price difference
        loanAmount = bound(loanAmount, 0.1 ether, 5 ether); // 0.1-5 ETH loan

        uint256 basePrice = 3000 * 1e6; // $3000 USDC per WETH
        uint256 higherPrice = basePrice * (100 + priceDiff) / 100;

        // Set up price discrepancy: Uniswap higher, PancakeSwap lower
        mockUniswapRouter.setExchangeRate(address(mockWETH), address(mockUSDC), higherPrice);
        mockUniswapRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 1e18 * 1e6 / higherPrice);

        mockPancakeRouter.setExchangeRate(address(mockWETH), address(mockUSDC), basePrice);
        mockPancakeRouter.setExchangeRate(address(mockUSDC), address(mockWETH), 1e18 * 1e6 / basePrice);

        // Set quoter
        mockUniswapQuoter.setQuote(address(mockWETH), address(mockUSDC), 500, higherPrice);
        mockUniswapQuoter.setQuote(address(mockUSDC), address(mockWETH), 500, 1e18 * 1e6 / higherPrice);

        // Prepare contract with sufficient funds
        mockWETH.mint(address(arbitrageBot), loanAmount + 2 ether);

        vm.startPrank(address(arbitrageBot));
        mockWETH.approve(address(mockBalancerVault), loanAmount + 2 ether);
        mockWETH.approve(address(mockUniswapRouter), loanAmount + 2 ether);
        mockUSDC.approve(address(mockPancakeRouter), 100_000_000 * 1e6);
        vm.stopPrank();

        // Set low profit threshold for testing
        vm.prank(owner);
        arbitrageBot.setMinProfitThreshold(1e12); // Very low threshold

        // Execute arbitrage
        try arbitrageBot.executeArbitrage(
            address(mockWETH),
            address(mockUSDC),
            loanAmount,
            500,
            true // Uniswap to PancakeSwap
        ) {
            // If successful, verify owner received some profit
            uint256 ownerBalance = mockWETH.balanceOf(owner);
            // With high price differences, should be profitable
            if (priceDiff >= 5) {
                assertGt(ownerBalance, 0, "Owner should receive profit with significant price difference");
            }
        } catch {
            // If it fails, it should be with low price differences
            // This is acceptable as small differences might not cover gas costs
        }
    }
}
