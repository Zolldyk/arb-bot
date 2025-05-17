// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArbitrageBot} from "../src/ArbitrageBot.sol";
import {IBalancerVault} from "../src/Interfaces/IBalancerVault.sol";
import {IUniswapV3SwapRouter} from "../src/Interfaces/IUniswapV3SwapRouter.sol";
import {IPancakeRouter} from "../src/Interfaces/IPancakeRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArbitrageBotTest
 * @notice Test contract for ArbitrageBot
 * @dev Uses Foundry's testing framework with mainnet forking capabilities
 */
contract ArbitrageBotTest is Test {
    // Contract to test
    ArbitrageBot public arbitrageBot;

    // Mainnet contract addresses
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PANCAKE_ROUTER = 0xEfF92A263d31888d860bD50809A8D171709b7b1c;
    address constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    // Token addresses for testing (mainnet)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Price feeds (Ethereum mainnet)
    address constant WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Test accounts
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    // Minimum profit threshold (10 USDC = 10 * 10^6)
    uint256 constant MIN_PROFIT_THRESHOLD = 10 * 1e6;

    /**
     * @notice Setup function that runs before each test
     */
    function setUp() public {
        // Fork Ethereum mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        // Deploy the arbitrage bot with owner
        vm.startPrank(owner);
        arbitrageBot =
            new ArbitrageBot(BALANCER_VAULT, UNISWAP_ROUTER, PANCAKE_ROUTER, UNISWAP_QUOTER, MIN_PROFIT_THRESHOLD);

        // Set price feeds
        arbitrageBot.setPriceFeed(WETH, WETH_USD_FEED);
        arbitrageBot.setPriceFeed(USDC, USDC_USD_FEED);
        arbitrageBot.setPriceFeed(DAI, DAI_USD_FEED);
        vm.stopPrank();
    }

    /**
     * @notice Test constructor sets initial values correctly
     */
    function testConstructor() public view {
        (
            address balancerVault,
            address uniswapRouter,
            address pancakeRouter,
            address uniswapQuoter,
            uint256 minProfitThreshold,
            uint256 slippageTolerance,
            uint256 maxGasPrice,
            bool isActive
        ) = arbitrageBot.getConfig();

        assertEq(balancerVault, BALANCER_VAULT, "Balancer vault address should match");
        assertEq(uniswapRouter, UNISWAP_ROUTER, "Uniswap router address should match");
        assertEq(pancakeRouter, PANCAKE_ROUTER, "PancakeSwap router address should match");
        assertEq(uniswapQuoter, UNISWAP_QUOTER, "Uniswap quoter address should match");
        assertEq(minProfitThreshold, MIN_PROFIT_THRESHOLD, "Min profit threshold should match");
        assertEq(slippageTolerance, 50, "Default slippage tolerance should be 0.5%");
        assertEq(maxGasPrice, 100 gwei, "Default max gas price should be 100 gwei");
        assertTrue(isActive, "Contract should be active by default");
    }

    /**
     * @notice Test that only the owner can call admin functions
     */
    function testOnlyOwnerFunctions() public {
        vm.startPrank(user);

        // Try to set minimum profit threshold
        vm.expectRevert();
        arbitrageBot.setMinProfitThreshold(1e6);

        // Try to set slippage tolerance
        vm.expectRevert();
        arbitrageBot.setSlippageTolerance(100);

        // Try to set max gas price
        vm.expectRevert();
        arbitrageBot.setMaxGasPrice(50 gwei);

        // Try to toggle active status
        vm.expectRevert();
        arbitrageBot.toggleActive();

        // Try to emergency withdraw
        vm.expectRevert();
        arbitrageBot.emergencyWithdraw(WETH);

        // Try to set price feed
        vm.expectRevert();
        arbitrageBot.setPriceFeed(WETH, WETH_USD_FEED);

        vm.stopPrank();
    }

    /**
     * @notice Test that the owner can set configuration parameters
     */
    function testOwnerCanSetParameters() public {
        vm.startPrank(owner);

        // Test setting min profit threshold
        arbitrageBot.setMinProfitThreshold(20 * 1e6);

        // Test setting slippage tolerance
        arbitrageBot.setSlippageTolerance(100);

        // Test setting max gas price
        arbitrageBot.setMaxGasPrice(100 gwei);

        // Test toggling active status
        arbitrageBot.toggleActive();

        // Verify values were set correctly
        (,,,, uint256 minProfitThreshold, uint256 slippageTolerance, uint256 maxGasPrice, bool isActive) =
            arbitrageBot.getConfig();

        assertEq(minProfitThreshold, 20 * 1e6, "Min profit threshold should be updated");
        assertEq(slippageTolerance, 100, "Slippage tolerance should be updated");
        assertEq(maxGasPrice, 100 gwei, "Max gas price should be updated");
        assertFalse(isActive, "Contract should be inactive after toggle");

        vm.stopPrank();
    }

    /**
     * @notice Test that slippage tolerance cannot be set too high
     */
    function testSlippageToleranceLimit() public {
        vm.startPrank(owner);

        // Should succeed with 1000 (10%)
        arbitrageBot.setSlippageTolerance(1000);

        // Should fail with 1001 (>10%)
        vm.expectRevert();
        arbitrageBot.setSlippageTolerance(1001);

        vm.stopPrank();
    }

    /**
     * @notice Test emergency withdrawal functionality
     */
    function testEmergencyWithdraw() public {
        // Give the contract some WETH
        deal(WETH, address(arbitrageBot), 1 ether);

        // Check initial balances
        uint256 initialContractBalance = IERC20(WETH).balanceOf(address(arbitrageBot));
        uint256 initialOwnerBalance = IERC20(WETH).balanceOf(owner);

        assertEq(initialContractBalance, 1 ether, "Contract should have 1 WETH");

        // Emergency withdraw as owner
        vm.prank(owner);
        arbitrageBot.emergencyWithdraw(WETH);

        // Check final balances
        uint256 finalContractBalance = IERC20(WETH).balanceOf(address(arbitrageBot));
        uint256 finalOwnerBalance = IERC20(WETH).balanceOf(owner);

        assertEq(finalContractBalance, 0, "Contract should have 0 WETH after withdrawal");
        assertEq(finalOwnerBalance, initialOwnerBalance + 1 ether, "Owner should have received 1 WETH");
    }

    /**
     * @notice Test price feed functionality
     */
    function testPriceFeed() public {
        vm.startPrank(owner);

        // Test setting price feed
        arbitrageBot.setPriceFeed(DAI, DAI_USD_FEED);

        // Verify price feed was set correctly
        address priceFeed = arbitrageBot.getPriceFeed(DAI);
        assertEq(priceFeed, DAI_USD_FEED, "Price feed should be set correctly");

        vm.stopPrank();
    }
}
