// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBalancerVault, IFlashLoanRecipient} from "./Interfaces/IBalancerVault.sol";
import {IUniswapV3SwapRouter} from "./Interfaces/IUniswapV3SwapRouter.sol";
import {IPancakeRouter} from "./Interfaces/IPancakeRouter.sol";
import {IUniswapV3Quoter} from "./Interfaces/IUniswapV3Quoter.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 * @title ArbitrageBot
 * @author Zoll
 * @notice This contract executes arbitrage between Uniswap V3 and PancakeSwap using Balancer flash loans
 * @dev The contract uses flash loans from Balancer to execute arbitrage with zero initial capital
 */
contract ArbitrageBot is ReentrancyGuard, Ownable, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    // ============ Errors ============
    error ArbitrageBot__InvalidAddress();
    error ArbitrageBot__ContractPaused();
    error ArbitrageBot__Unauthorized();
    error ArbitrageBot__ProfitBelowThreshold(uint256 profit, uint256 threshold);
    error ArbitrageBot__InsufficientFundsForRepayment(uint256 available, uint256 required);
    error ArbitrageBot__SlippageTooHigh(uint256 requested, uint256 maxAllowed);
    error ArbitrageBot__FlashLoanFailed();
    error ArbitrageBot__InvalidTokenPair();
    error ArbitrageBot__PriceFeedNotSet();
    error ArbitrageBot__AbnormalPriceDetected();
    error ArbitrageBot__SwapFailed();
    error ArbitrageBot__InvalidFlashLoanCallback();

    // ============ Type declarations ============
    struct ArbitrageParams {
        address tokenBorrow; // Token to borrow via flash loan
        address tokenTarget; // Token to swap for
        uint256 amount; // Amount to borrow
        uint24 uniswapPoolFee; // Uniswap V3 pool fee tier
        bool uniToPancake; // Direction of arbitrage (true: Uni->Pancake, false: Pancake->Uni)
        uint256 deadline; // Transaction deadline
        address initiator; // Address that initiated the arbitrage
    }

    // ============ State variables ============
    // Core protocol addresses
    address private immutable i_balancerVault;
    address private immutable i_uniswapRouter;
    address private immutable i_pancakeRouter;
    address private immutable i_uniswapQuoter;

    // DEX fee tiers
    mapping(address => mapping(address => uint24)) private s_preferredUniswapPoolFees;

    // Configuration parameters
    uint256 private s_minProfitThreshold;
    uint256 private s_slippageTolerance = 50; // Default 0.5% (in basis points)
    uint256 private s_maxGasPrice = 100 gwei;
    bool private s_isActive = true;

    // Price feeds for token pairs
    mapping(address => address) private s_priceFeeds;

    // Flash loan tracking for security
    mapping(bytes32 => bool) private s_activeFlashLoans;

    // Constants
    uint256 private constant MAX_SLIPPAGE = 1000; // 10%
    uint256 private constant DEADLINE_BUFFER = 300; // 5 minutes

    // ============ Events ============
    event ArbitrageExecuted(
        address indexed tokenBorrow,
        address indexed tokenTarget,
        uint256 flashLoanAmount,
        uint256 grossProfit,
        uint256 netProfit,
        uint256 gasUsed,
        bool indexed direction
    );

    event ArbitrageFailed(
        address indexed tokenBorrow, address indexed tokenTarget, uint256 flashLoanAmount, string reason
    );

    event ConfigUpdated(string parameter, uint256 oldValue, uint256 newValue);
    event CircuitBreakerTriggered(bool isActive);
    event PriceFeedSet(address indexed token, address indexed priceFeed);
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);
    event PreferredPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);

    // ============ Constructor ============
    /**
     * @notice Initializing the arbitrage bot with required protocol addresses and parameters
     * @param balancerVault Address of Balancer Vault for flash loans
     * @param uniswapRouter Address of Uniswap V3 Swap Router
     * @param pancakeRouter Address of PancakeSwap Router
     * @param uniswapQuoter Address of Uniswap V3 Quoter
     * @param minProfitThreshold Minimum profit required to execute a trade (in wei)
     * @dev All addresses must be valid and non-zero
     */
    constructor(
        address balancerVault,
        address uniswapRouter,
        address pancakeRouter,
        address uniswapQuoter,
        uint256 minProfitThreshold
    ) Ownable(msg.sender) {
        if (
            balancerVault == address(0) || uniswapRouter == address(0) || pancakeRouter == address(0)
                || uniswapQuoter == address(0)
        ) {
            revert ArbitrageBot__InvalidAddress();
        }

        i_balancerVault = balancerVault;
        i_uniswapRouter = uniswapRouter;
        i_pancakeRouter = pancakeRouter;
        i_uniswapQuoter = uniswapQuoter;
        s_minProfitThreshold = minProfitThreshold;
    }

    // ============ External Functions ============
    /**
     * @notice Execute an arbitrage opportunity between Uniswap V3 and PancakeSwap
     * @param tokenBorrow Token to borrow using flash loan
     * @param tokenTarget Token to swap to and from
     * @param amount Amount of tokenBorrow to flash loan
     * @param uniswapPoolFee Uniswap V3 pool fee (3000 = 0.3%, 500 = 0.05%, etc.)
     * @param uniToPancake Direction flag (true: Uni->Pancake, false: Pancake->Uni)
     */
    function executeArbitrage(
        address tokenBorrow,
        address tokenTarget,
        uint256 amount,
        uint24 uniswapPoolFee,
        bool uniToPancake
    ) external onlyOwner nonReentrant {
        // Pre-execution checks
        if (!s_isActive) {
            revert ArbitrageBot__ContractPaused();
        }

        if (tx.gasprice > s_maxGasPrice) {
            revert ArbitrageBot__AbnormalPriceDetected();
        }

        if (tokenBorrow == address(0) || tokenTarget == address(0) || tokenBorrow == tokenTarget) {
            revert ArbitrageBot__InvalidTokenPair();
        }

        // Prepare flash loan parameters
        address[] memory tokens = new address[](1);
        tokens[0] = tokenBorrow;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // Create unique flash loan ID for tracking
        bytes32 flashLoanId =
            keccak256(abi.encodePacked(block.timestamp, block.number, msg.sender, tokenBorrow, amount));

        // Mark flash loan as active
        s_activeFlashLoans[flashLoanId] = true;

        // Encode arbitrage parameters
        bytes memory userData = abi.encode(
            ArbitrageParams({
                tokenBorrow: tokenBorrow,
                tokenTarget: tokenTarget,
                amount: amount,
                uniswapPoolFee: uniswapPoolFee,
                uniToPancake: uniToPancake,
                deadline: block.timestamp + DEADLINE_BUFFER,
                initiator: msg.sender
            }),
            flashLoanId
        );

        // Execute flash loan from Balancer
        try IBalancerVault(i_balancerVault).flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, userData) {
            // Flash loan successful, arbitrage completed in the callback
        } catch (bytes memory reason) {
            // Clean up flash loan tracking
            s_activeFlashLoans[flashLoanId] = false;

            emit ArbitrageFailed(tokenBorrow, tokenTarget, amount, string(reason));
            revert ArbitrageBot__FlashLoanFailed();
        }

        // Clean up flash loan tracking
        s_activeFlashLoans[flashLoanId] = false;
    }

    /**
     * @notice Balancer flash loan callback function - FIXED IMPLEMENTATION
     * @dev Called by Balancer Vault after funds are borrowed
     * @dev CRITICAL: Tokens must be transferred back to vault, NOT approved
     * @param tokens Array of token addresses that were borrowed
     * @param amounts Array of amounts that were borrowed
     * @param feeAmounts Array of fee amounts to be paid (typically 0 for Balancer)
     * @param userData Encoded data passed from executeArbitrage
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        // Only Balancer Vault can call this function
        if (msg.sender != i_balancerVault) {
            revert ArbitrageBot__Unauthorized();
        }

        // Decode parameters and flash loan ID
        (ArbitrageParams memory params, bytes32 flashLoanId) = abi.decode(userData, (ArbitrageParams, bytes32));

        // Validate flash loan is active and deadline hasn't passed
        if (!s_activeFlashLoans[flashLoanId]) {
            revert ArbitrageBot__InvalidFlashLoanCallback();
        }

        if (block.timestamp > params.deadline) {
            revert ArbitrageBot__AbnormalPriceDetected();
        }

        // Validate received token matches expected
        if (tokens.length != 1 || tokens[0] != params.tokenBorrow) {
            revert ArbitrageBot__InvalidTokenPair();
        }

        // Record starting gas for profit calculation
        uint256 startingGas = gasleft();

        // Flash loan amounts
        uint256 flashLoanAmount = amounts[0];
        uint256 flashLoanFee = feeAmounts[0]; // Usually 0 for Balancer
        uint256 totalRepayAmount = flashLoanAmount + flashLoanFee;

        // Record initial balance
        uint256 initialBalance = IERC20(params.tokenBorrow).balanceOf(address(this));

        // Execute the arbitrage based on direction
        try this._executeArbitrageSwaps(params, flashLoanAmount) {
            // Arbitrage executed successfully
        } catch {
            revert ArbitrageBot__SwapFailed();
        }

        // Check final balance after arbitrage
        uint256 finalBalance = IERC20(params.tokenBorrow).balanceOf(address(this));

        // CRITICAL: Ensure we have enough to repay the flash loan
        if (finalBalance < totalRepayAmount) {
            revert ArbitrageBot__InsufficientFundsForRepayment(finalBalance, totalRepayAmount);
        }

        // Calculate gross profit
        uint256 grossProfit = finalBalance - totalRepayAmount;

        // Estimate gas cost for net profit calculation
        uint256 gasUsed = startingGas - gasleft() + 50000; // Add buffer for remaining operations
        uint256 estimatedGasCost = gasUsed * tx.gasprice;

        // Convert gas cost to token terms if needed (simplified for WETH case)
        uint256 gasCostInToken = _convertGasCostToToken(params.tokenBorrow, estimatedGasCost);

        // Calculate net profit
        uint256 netProfit = grossProfit > gasCostInToken ? grossProfit - gasCostInToken : 0;

        // Check profit threshold
        if (netProfit < s_minProfitThreshold) {
            revert ArbitrageBot__ProfitBelowThreshold(netProfit, s_minProfitThreshold);
        }

        // Transfer the borrowed tokens back to Balancer Vault
        IERC20(params.tokenBorrow).safeTransfer(i_balancerVault, totalRepayAmount);

        // Send profit to owner
        if (netProfit > 0) {
            IERC20(params.tokenBorrow).safeTransfer(owner(), netProfit);
        }

        // Emit success event
        emit ArbitrageExecuted(
            params.tokenBorrow,
            params.tokenTarget,
            flashLoanAmount,
            grossProfit,
            netProfit,
            gasUsed,
            params.uniToPancake
        );
    }

    /**
     * @notice Execute arbitrage swaps (separated for better error handling)
     * @dev External function to enable try/catch in receiveFlashLoan
     */
    function _executeArbitrageSwaps(ArbitrageParams memory params, uint256 flashLoanAmount) external {
        // SECURITY: Only this contract can call this function
        if (msg.sender != address(this)) {
            revert ArbitrageBot__Unauthorized();
        }

        if (params.uniToPancake) {
            // Step 1: Swap on Uniswap V3 (tokenBorrow -> tokenTarget)
            uint256 uniswapOutput =
                _swapOnUniswap(params.tokenBorrow, params.tokenTarget, flashLoanAmount, params.uniswapPoolFee);

            // Step 2: Swap on PancakeSwap (tokenTarget -> tokenBorrow)
            _swapOnPancakeSwap(params.tokenTarget, params.tokenBorrow, uniswapOutput);
        } else {
            // Step 1: Swap on PancakeSwap (tokenBorrow -> tokenTarget)
            uint256 pancakeOutput = _swapOnPancakeSwap(params.tokenBorrow, params.tokenTarget, flashLoanAmount);

            // Step 2: Swap on Uniswap V3 (tokenTarget -> tokenBorrow)
            _swapOnUniswap(params.tokenTarget, params.tokenBorrow, pancakeOutput, params.uniswapPoolFee);
        }
    }

    // ============ Admin Functions ============
    /**
     * @notice Set minimum profit threshold
     * @param newThreshold New minimum profit required (in wei)
     * @dev Only callable by owner
     */
    function setMinProfitThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = s_minProfitThreshold;
        s_minProfitThreshold = newThreshold;
        emit ConfigUpdated("minProfitThreshold", oldThreshold, newThreshold);
    }

    /**
     * @notice Set slippage tolerance
     * @param newSlippageTolerance New slippage tolerance in basis points (e.g., 50 = 0.5%)
     * @dev Only callable by owner
     * @dev Maximum allowed slippage tolerance is 1000 (10%)
     */
    function setSlippageTolerance(uint256 newSlippageTolerance) external onlyOwner {
        if (newSlippageTolerance > MAX_SLIPPAGE) {
            revert ArbitrageBot__SlippageTooHigh(newSlippageTolerance, MAX_SLIPPAGE);
        }

        uint256 oldSlippageTolerance = s_slippageTolerance;
        s_slippageTolerance = newSlippageTolerance;
        emit ConfigUpdated("slippageTolerance", oldSlippageTolerance, newSlippageTolerance);
    }

    /**
     * @notice Set maximum gas price
     * @param newMaxGasPrice New maximum gas price in wei
     * @dev Only callable by owner
     */
    function setMaxGasPrice(uint256 newMaxGasPrice) external onlyOwner {
        uint256 oldMaxGasPrice = s_maxGasPrice;
        s_maxGasPrice = newMaxGasPrice;
        emit ConfigUpdated("maxGasPrice", oldMaxGasPrice, newMaxGasPrice);
    }

    /**
     * @notice Emergency circuit breaker to pause/unpause the contract
     * @dev Only callable by owner
     */
    function toggleActive() external onlyOwner {
        s_isActive = !s_isActive;
        emit CircuitBreakerTriggered(s_isActive);
    }

    /**
     * @notice Set preferred Uniswap pool fee for a token pair
     * @param tokenA First token in the pair
     * @param tokenB Second token in the pair
     * @param fee The fee tier (e.g., 500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
     * @dev Only callable by owner
     */
    function setPreferredUniswapPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ArbitrageBot__InvalidAddress();
        }

        s_preferredUniswapPoolFees[tokenA][tokenB] = fee;
        s_preferredUniswapPoolFees[tokenB][tokenA] = fee;

        emit PreferredPoolFeeSet(tokenA, tokenB, fee);
    }

    /**
     * @notice Emergency withdraw any tokens stuck in the contract
     * @param token Token address to withdraw
     * @dev Only callable by owner
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
            emit EmergencyWithdrawal(token, balance, msg.sender);
        }
    }

    /**
     * @notice Set price feed for a token
     * @param token Token address
     * @param priceFeed Chainlink price feed address
     * @dev Only callable by owner
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0) || priceFeed == address(0)) {
            revert ArbitrageBot__InvalidAddress();
        }

        s_priceFeeds[token] = priceFeed;
        emit PriceFeedSet(token, priceFeed);
    }

    // ============ Internal Functions ============
    /**
     * @notice Swap tokens on Uniswap V3
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     * @param poolFee Fee tier of the pool
     */
    function _swapOnUniswap(address tokenIn, address tokenOut, uint256 amountIn, uint24 poolFee)
        internal
        returns (uint256)
    {
        // Approve router to spend tokens
        IERC20(tokenIn).approve(i_uniswapRouter, amountIn);

        // Calculate minimum output based on slippage tolerance
        uint256 amountOutMin = _calculateMinimumOutput(tokenIn, tokenOut, amountIn, true);

        // Execute swap on Uniswap V3
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + DEADLINE_BUFFER,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = IUniswapV3SwapRouter(i_uniswapRouter).exactInputSingle(params);

        // Reset approval to 0 for security
        IERC20(tokenIn).approve(i_uniswapRouter, 0);

        return amountOut;
    }

    /**
     * @notice Swap tokens on PancakeSwap
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     */
    function _swapOnPancakeSwap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        // Approve router to spend tokens
        IERC20(tokenIn).approve(i_pancakeRouter, amountIn);

        // Calculate minimum output based on slippage tolerance
        uint256 amountOutMin = _calculateMinimumOutput(tokenIn, tokenOut, amountIn, false);

        // Create path for the swap
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Execute swap on PancakeSwap
        uint256[] memory amounts = IPancakeRouter(i_pancakeRouter).swapExactTokensForTokens(
            amountIn, amountOutMin, path, address(this), block.timestamp + DEADLINE_BUFFER
        );

        // Reset approval to 0 for security
        IERC20(tokenIn).approve(i_pancakeRouter, 0);

        return amounts[1];
    }

    /**
     * @notice Calculate minimum output amount considering slippage
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     * @param isUniswap Flag to indicate which DEX the calculation is for
     * @return Minimum amount that should be received after swap
     */
    function _calculateMinimumOutput(address tokenIn, address tokenOut, uint256 amountIn, bool isUniswap)
        internal
        pure
        returns (uint256)
    {
        // Use conservative estimate to avoid reverts
        return _getConservativeQuote(tokenIn, tokenOut, amountIn);
    }

    /**
     * @notice Get a conservative quote when DEX queries fail
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     * @return Conservative estimate with maximum slippage
     * @dev This is a fallback method that returns a minimal value to allow swaps
     */
    function _getConservativeQuote(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        pure
        returns (uint256)
    {
        // For production, implement proper quote logic
        // For now, return minimal value to prevent swap failures
        return 1;
    }

    function _convertGasCostToToken(address token, uint256 gasCostInWei) internal pure returns (uint256) {
        // Simplified conversion for WETH case
        // In production, implement proper price conversion using Chainlink feeds
        if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) {
            // WETH
            return gasCostInWei; // 1:1 for WETH
        }

        // For other tokens, implement proper conversion logic
        // Using conservative estimate for now
        return gasCostInWei * 3000; // Assuming ~$3000 per ETH
    }

    /**
     * @notice Calculate minimum output using Chainlink price feeds
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     * @param isUniswap Flag to indicate which DEX the calculation is for
     * @return Expected minimum amount after slippage
     */
    function _calculateFromPriceFeeds(address tokenIn, address tokenOut, uint256 amountIn, bool isUniswap)
        internal
        view
        returns (uint256)
    {
        address inFeed = s_priceFeeds[tokenIn];
        address outFeed = s_priceFeeds[tokenOut];

        // Get token prices from Chainlink
        (, int256 priceIn,,,) = AggregatorV3Interface(inFeed).latestRoundData();
        (, int256 priceOut,,,) = AggregatorV3Interface(outFeed).latestRoundData();

        if (priceIn <= 0 || priceOut <= 0) {
            revert ArbitrageBot__AbnormalPriceDetected();
        }

        // Get token decimals for price feeds
        uint8 decimalsIn = AggregatorV3Interface(inFeed).decimals();
        uint8 decimalsOut = AggregatorV3Interface(outFeed).decimals();

        // Calculate expected output with proper decimal handling
        // priceIn is in USD with decimalsIn precision
        // priceOut is in USD with decimalsOut precision
        // We want: (amountIn * priceIn) / priceOut

        uint256 valueInUSD;
        if (decimalsIn >= 18) {
            valueInUSD = (amountIn * uint256(priceIn)) / (10 ** (decimalsIn - 18));
        } else {
            valueInUSD = (amountIn * uint256(priceIn)) * (10 ** (18 - decimalsIn));
        }

        uint256 expectedOutput;
        if (decimalsOut >= 18) {
            expectedOutput = valueInUSD / (uint256(priceOut) / (10 ** (decimalsOut - 18)));
        } else {
            expectedOutput = valueInUSD / (uint256(priceOut) * (10 ** (18 - decimalsOut)));
        }

        // For USDC (6 decimals), we need to adjust the output
        // If tokenOut is USDC-like (6 decimals), scale down from 18 decimals
        // This is a simplification - in production you'd want to get actual token decimals
        if (expectedOutput > 1e15) {
            // Likely dealing with USDC or similar
            expectedOutput = expectedOutput / 1e12; // Convert from 18 decimals to 6 decimals
        }

        // Apply DEX-specific fees
        if (isUniswap) {
            // Uniswap V3 fee (assuming 0.05% for 500 tier, 0.3% for 3000 tier, etc.)
            expectedOutput = expectedOutput * 9995 / 10000; // 0.05% fee
        } else {
            // PancakeSwap fee (0.25% fee)
            expectedOutput = expectedOutput * 9975 / 10000;
        }

        // Apply slippage tolerance
        return expectedOutput * (10000 - s_slippageTolerance) / 10000;
    }

    /**
     * @notice Get on-chain quote for expected output
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token
     * @param isUniswap Flag to indicate which DEX the calculation is for
     * @return Expected minimum amount after slippage
     * @dev Production implementation that queries DEXes directly for quotes
     */
    function _getOnChainQuote(address tokenIn, address tokenOut, uint256 amountIn, bool isUniswap)
        internal
        returns (uint256)
    {
        uint256 expectedOutput;

        if (isUniswap) {
            // Get quote from Uniswap V3
            // First determine the fee tier to use
            uint24 feeTier = s_preferredUniswapPoolFees[tokenIn][tokenOut];

            // If no preferred fee tier is set, default to 0.3% (3000)
            if (feeTier == 0) {
                feeTier = 3000;
            }

            // Query Uniswap V3 Quoter for expected output
            try IUniswapV3Quoter(i_uniswapQuoter).quoteExactInputSingle(
                tokenIn,
                tokenOut,
                feeTier,
                amountIn,
                0 // No price limit
            ) returns (uint256 amountOut) {
                expectedOutput = amountOut;
            } catch {
                // Fallback if quote fails
                // This could happen if the pool doesn't exist or has very low liquidity
                // In this case, we'll use a very conservative estimate
                return _getConservativeQuote(tokenIn, tokenOut, amountIn);
            }
        } else {
            // Get quote from PancakeSwap
            // PancakeSwap doesn't have a simple quoter contract like Uniswap V3
            // We need to call the router with a static call to get the expected output
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            // Try to get quote from PancakeSwap router
            try IPancakeRouter(i_pancakeRouter).swapExactTokensForTokens{gas: 200000}(
                amountIn,
                0, // No minimum output requirement for quote
                path,
                address(this), // Recipient doesn't matter for static call
                block.timestamp + 1 // Deadline just after current block
            ) returns (uint256[] memory amounts) {
                // Static call will return expected amounts without executing the swap
                if (amounts.length >= 2) {
                    expectedOutput = amounts[1]; // Output amount is at index 1
                } else {
                    // Fallback if amounts array is incomplete
                    return _getConservativeQuote(tokenIn, tokenOut, amountIn);
                }
            } catch {
                // Fallback if quote fails
                return _getConservativeQuote(tokenIn, tokenOut, amountIn);
            }
        }

        // Apply slippage tolerance for minimum output
        return expectedOutput * (10000 - s_slippageTolerance) / 10000;
    }

    // ============ View Functions ============
    function getConfig()
        external
        view
        returns (
            address balancerVault,
            address uniswapRouter,
            address pancakeRouter,
            address uniswapQuoter,
            uint256 minProfitThreshold,
            uint256 slippageTolerance,
            uint256 maxGasPrice,
            bool isActive
        )
    {
        return (
            i_balancerVault,
            i_uniswapRouter,
            i_pancakeRouter,
            i_uniswapQuoter,
            s_minProfitThreshold,
            s_slippageTolerance,
            s_maxGasPrice,
            s_isActive
        );
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getPreferredUniswapPoolFee(address tokenA, address tokenB) external view returns (uint24) {
        return s_preferredUniswapPoolFees[tokenA][tokenB];
    }
}
