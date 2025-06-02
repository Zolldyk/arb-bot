// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ArbitrageBot} from "../src/ArbitrageBot.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployArbitrageBot
 * @notice Deployment script for ArbitrageBot with encrypted key support
 * @dev Use with: forge script script/DeployArbitrageBot.s.sol --rpc-url $ETH_RPC_URL --account devTestKey2 --sender <your_address> --broadcast
 */
contract DeployArbitrageBot is Script {
    // Mainnet addresses
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PANCAKE_ROUTER = 0xEfF92A263d31888d860bD50809A8D171709b7b1c;
    address constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    // Price feeds (Ethereum mainnet)
    address constant WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // Token addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Configuration
    uint256 constant MIN_PROFIT_THRESHOLD = 10 * 1e6; // 10 USDC

    function run() external {
        console.log("Deploying ArbitrageBot with encrypted key: devTestKey2");
        console.log("Deployer balance:", msg.sender.balance);

        vm.startBroadcast();

        // Deploy the ArbitrageBot
        ArbitrageBot arbitrageBot =
            new ArbitrageBot(BALANCER_VAULT, UNISWAP_ROUTER, PANCAKE_ROUTER, UNISWAP_QUOTER, MIN_PROFIT_THRESHOLD);

        console.log("ArbitrageBot deployed at:", address(arbitrageBot));

        // Set up price feeds
        arbitrageBot.setPriceFeed(WETH, WETH_USD_FEED);
        arbitrageBot.setPriceFeed(USDC, USDC_USD_FEED);
        arbitrageBot.setPriceFeed(DAI, DAI_USD_FEED);

        // Set preferred Uniswap pool fees
        arbitrageBot.setPreferredUniswapPoolFee(WETH, USDC, 500); // 0.05%
        arbitrageBot.setPreferredUniswapPoolFee(WETH, DAI, 3000); // 0.3%
        arbitrageBot.setPreferredUniswapPoolFee(USDC, DAI, 100); // 0.01%

        // Set conservative initial parameters
        arbitrageBot.setSlippageTolerance(50); // 0.5%
        arbitrageBot.setMaxGasPrice(150 gwei); // Conservative gas price limit

        vm.stopBroadcast();

        console.log("Setup completed successfully!");
        console.log("Contract Address:", address(arbitrageBot));
        console.log("Owner Address:", arbitrageBot.owner());
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify the contract on Etherscan:");
        console.log("   forge verify-contract <CONTRACT_ADDRESS> ArbitrageBot --etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("2. Test on small amounts first");
        console.log("3. Monitor gas prices and adjust maxGasPrice as needed");
        console.log("4. Set up your searcher bot to detect opportunities");
        console.log("5. Fund the contract owner address with ETH for gas fees");
    }

    /**
     * @notice Deploy to Sepolia testnet for testing
     * @dev Use with: forge script script/DeployArbitrageBot.s.sol --sig "runTestnet()" --rpc-url $SEPOLIA_RPC_URL --account devTestKey2 --sender <your_address> --broadcast
     */
    function runTestnet() external {
        // Sepolia testnet addresses
        address balancerVault = 0xfA8449189744799aD2AcE7e0EBAC8BB7575eff47; // Sepolia Balancer Vault
        address uniswapRouter = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E; // Sepolia Uniswap Router
        // Note: PancakeSwap might not be available on Sepolia, use mock or alternative DEX
        address pancakeRouter = uniswapRouter; // Fallback to Uniswap for testing
        address uniswapQuoter = 0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3; // Sepolia Uniswap Quoter

        console.log("Deploying to Sepolia testnet with devTestKey2...");

        vm.startBroadcast();

        ArbitrageBot arbitrageBot = new ArbitrageBot(
            balancerVault,
            uniswapRouter,
            pancakeRouter,
            uniswapQuoter,
            1 * 1e6 // Lower threshold for testing (1 USDC)
        );

        console.log("Testnet ArbitrageBot deployed at:", address(arbitrageBot));
        console.log("Owner:", arbitrageBot.owner());

        // Set lower gas price limit for testnet
        arbitrageBot.setMaxGasPrice(50 gwei);
        arbitrageBot.setSlippageTolerance(100); // 1% for more lenient testing

        vm.stopBroadcast();

        console.log("Testnet deployment completed!");
        console.log("Remember to:");
        console.log("1. Get testnet ETH from faucets");
        console.log("2. Test with small amounts");
        console.log("3. Verify contract functionality before mainnet");
    }

    /**
     * @notice Get deployment info for your encrypted key
     */
    function getDeploymentInfo() external view {
        console.log("=== Deployment Information ===");
        console.log("Using encrypted key: devTestKey2");
        console.log("Sender address: %s", msg.sender);
        console.log("Current network chain ID: %s", block.chainid);
        console.log("");
        console.log("=== Command to deploy to mainnet ===");
        console.log("forge script script/DeployArbitrageBot.s.sol \\");
        console.log("  --rpc-url $ETH_RPC_URL \\");
        console.log("  --account devTestKey2 \\");
        console.log("  --sender %s \\", msg.sender);
        console.log("  --broadcast \\");
        console.log("  --verify");
        console.log("");
        console.log("=== Command to deploy to testnet ===");
        console.log("forge script script/DeployArbitrageBot.s.sol \\");
        console.log("  --sig 'runTestnet()' \\");
        console.log("  --rpc-url $SEPOLIA_RPC_URL \\");
        console.log("  --account devTestKey2 \\");
        console.log("  --sender %s \\", msg.sender);
        console.log("  --broadcast");
    }
}
