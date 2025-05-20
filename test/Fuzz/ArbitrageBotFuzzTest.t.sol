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
}
