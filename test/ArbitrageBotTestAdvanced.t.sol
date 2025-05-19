// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArbitrageBot} from "../src/ArbitrageBot.sol";
import {IBalancerVault} from "../src/Interfaces/IBalancerVault.sol";
import {IUniswapV3SwapRouter} from "../src/Interfaces/IUniswapV3SwapRouter.sol";
import {IPancakeRouter} from "../src/Interfaces/IPancakeRouter.sol";
import {IUniswapV3Quoter} from "../src/Interfaces/IUniswapV3Quoter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArbitrageBotTestAdvanced
 * @author Zoll
 * @notice Advanced test contract for comprehensive testing of ArbitrageBot functionality
 * @dev Uses Foundry's testing framework with mainnet forking and various test techniques
 */
contract ArbitrageBotTestAdvanced is Test {
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
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Price feeds (Ethereum mainnet)
    address constant WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Test accounts
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    // Minimum profit threshold (10 USDC = 10 * 10^6)
    uint256 constant MIN_PROFIT_THRESHOLD = 10 * 1e6;

    // Fork block number
    uint256 public forkBlock = 16900000; // Ethereum block from early 2023


    /**
     * @notice Setup function that runs before each test
     */

    function setUp() public virtual {
        // Fork Ethereum mainnet at a specific block
        vm.createSelectFork("ETH_RPC_URL", forkBlock);
        
        // Deploy the arbitrage bot with owner
        vm.startPrank(owner);
        arbitrageBot = new ArbitrageBot(
            BALANCER_VAULT,
            UNISWAP_ROUTER,
            PANCAKE_ROUTER,
            UNISWAP_QUOTER,
            MIN_PROFIT_THRESHOLD
        );
        
        // Set price feeds
        arbitrageBot.setPriceFeed(WETH, WETH_USD_FEED);
        arbitrageBot.setPriceFeed(USDC, USDC_USD_FEED);
        arbitrageBot.setPriceFeed(DAI, DAI_USD_FEED);
        
        // Set preferred Uniswap pool fees for token pairs
        arbitrageBot.setPreferredUniswapPoolFee(WETH, USDC, 500);  // 0.05%
        arbitrageBot.setPreferredUniswapPoolFee(WETH, DAI, 3000);  // 0.3%
        arbitrageBot.setPreferredUniswapPoolFee(USDC, DAI, 100);   // 0.01%
        
        vm.stopPrank();
    }
}
