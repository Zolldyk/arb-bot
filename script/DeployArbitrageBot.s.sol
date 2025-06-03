// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ArbitrageBot} from "../src/ArbitrageBot.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployArbitrageBot
 * @notice Deployment script for ArbitrageBot contract
 * @dev Deploys to testnet or mainnet with proper configuration
 */
contract DeployArbitrageBot is Script {
    // Sepolia testnet addresses
    address constant SEPOLIA_BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant SEPOLIA_UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant SEPOLIA_PANCAKE_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14; // PancakeSwap V3 on Sepolia
    address constant SEPOLIA_UNISWAP_QUOTER = 0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3; // Uniswap V3 Quoter on Sepolia

    // Sepolia price feeds
    address constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant SEPOLIA_USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;

    // Sepolia token addresses
    address constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant SEPOLIA_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // USDC on Sepolia

    // Mainnet addresses
    address constant MAINNET_BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant MAINNET_UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant MAINNET_PANCAKE_ROUTER = 0xEfF92A263d31888d860bD50809A8D171709b7b1c;
    address constant MAINNET_UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    // Mainnet price feeds
    address constant MAINNET_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant MAINNET_USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant MAINNET_DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Mainnet token addresses
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Configuration
    uint256 constant MIN_PROFIT_THRESHOLD = 10 * 1e6; // 10 USDC minimum profit

    function run() external {
        // Get chain ID to determine which network we're deploying to
        uint256 chainId = block.chainid;

        // Start broadcasting transactions
        vm.startBroadcast();

        ArbitrageBot arbitrageBot;

        if (chainId == 11155111) {
            // Sepolia
            console.log("Deploying to Sepolia testnet...");
            arbitrageBot = deployToSepolia();
        } else if (chainId == 1) {
            // Mainnet
            console.log("Deploying to Ethereum mainnet...");
            arbitrageBot = deployToMainnet();
        } else {
            revert("Unsupported chain ID");
        }

        vm.stopBroadcast();

        // Log deployment information
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("ArbitrageBot deployed to:", address(arbitrageBot));
        console.log("Owner:", arbitrageBot.owner());

        // Get and log configuration
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

        console.log("=== CONFIGURATION ===");
        console.log("Balancer Vault:", balancerVault);
        console.log("Uniswap Router:", uniswapRouter);
        console.log("PancakeSwap Router:", pancakeRouter);
        console.log("Uniswap Quoter:", uniswapQuoter);
        console.log("Min Profit Threshold:", minProfitThreshold);
        console.log("Slippage Tolerance:", slippageTolerance);
        console.log("Max Gas Price:", maxGasPrice);
        console.log("Is Active:", isActive);

        console.log("=== NEXT STEPS ===");
        console.log("1. Verify the contract on Etherscan");
        console.log("2. Test arbitrage functionality");
        console.log("3. Monitor for profitable opportunities");

        if (chainId == 11155111) {
            console.log("4. Once tested, deploy to mainnet using the same script");
        }
    }

    function deployToSepolia() internal returns (ArbitrageBot) {
        console.log("Using Sepolia configuration...");

        // Deploy the ArbitrageBot
        ArbitrageBot arbitrageBot = new ArbitrageBot(
            SEPOLIA_BALANCER_VAULT,
            SEPOLIA_UNISWAP_ROUTER,
            SEPOLIA_PANCAKE_ROUTER,
            SEPOLIA_UNISWAP_QUOTER,
            MIN_PROFIT_THRESHOLD
        );

        // Configure price feeds
        arbitrageBot.setPriceFeed(SEPOLIA_WETH, SEPOLIA_ETH_USD_FEED);
        arbitrageBot.setPriceFeed(SEPOLIA_USDC, SEPOLIA_USDC_USD_FEED);

        // Set preferred Uniswap pool fees
        arbitrageBot.setPreferredUniswapPoolFee(SEPOLIA_WETH, SEPOLIA_USDC, 500); // 0.05%

        // Set conservative parameters for testnet
        arbitrageBot.setSlippageTolerance(100); // 1% slippage tolerance
        arbitrageBot.setMaxGasPrice(100 gwei); // Maximum 100 gwei

        console.log("Sepolia deployment configured successfully");
        return arbitrageBot;
    }

    function deployToMainnet() internal returns (ArbitrageBot) {
        console.log("Using Mainnet configuration...");

        // Deploy the ArbitrageBot
        ArbitrageBot arbitrageBot = new ArbitrageBot(
            MAINNET_BALANCER_VAULT,
            MAINNET_UNISWAP_ROUTER,
            MAINNET_PANCAKE_ROUTER,
            MAINNET_UNISWAP_QUOTER,
            MIN_PROFIT_THRESHOLD
        );

        // Configure price feeds
        arbitrageBot.setPriceFeed(MAINNET_WETH, MAINNET_ETH_USD_FEED);
        arbitrageBot.setPriceFeed(MAINNET_USDC, MAINNET_USDC_USD_FEED);
        arbitrageBot.setPriceFeed(MAINNET_DAI, MAINNET_DAI_USD_FEED);

        // Set preferred Uniswap pool fees for common pairs
        arbitrageBot.setPreferredUniswapPoolFee(MAINNET_WETH, MAINNET_USDC, 500); // 0.05%
        arbitrageBot.setPreferredUniswapPoolFee(MAINNET_WETH, MAINNET_DAI, 3000); // 0.3%
        arbitrageBot.setPreferredUniswapPoolFee(MAINNET_USDC, MAINNET_DAI, 100); // 0.01%

        // Set production parameters
        arbitrageBot.setSlippageTolerance(50); // 0.5% slippage tolerance
        arbitrageBot.setMaxGasPrice(150 gwei); // Maximum 150 gwei for mainnet

        console.log("Mainnet deployment configured successfully");
        return arbitrageBot;
    }
}
