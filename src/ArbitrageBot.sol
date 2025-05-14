// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============ Imports ============
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IUniswapV3SwapRouter} from "./interfaces/IUniswapV3SwapRouter.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

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
 * 
 */

contract ArbitrageBot is ReentrancyGuard, Ownable {
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


    // ============ Type declarations ============
    struct ArbitrageParams {
        address tokenBorrow;       // Token to borrow via flash loan
        address tokenTarget;       // Token to swap for
        uint256 amount;            // Amount to borrow
        uint24 uniswapPoolFee;     // Uniswap V3 pool fee tier
        bool uniToPancake;         // Direction of arbitrage (true: Uni->Pancake, false: Pancake->Uni)
    }

    // ============ State variables ============
    // Core protocol addresses
    address private immutable i_balancerVault;
    address private immutable i_uniswapRouter;
    address private immutable i_pancakeRouter;

    // Configuration parameters
    uint256 private s_minProfitThreshold;    // Minimum profit threshold in wei
    uint256 private s_slippageTolerance = 50; // Default 0.5% (in basis points)
    uint256 private s_maxGasPrice = 100 gwei; // Maximum gas price for profitable transactions
    bool private s_isActive = true;          // Circuit breaker
    
    // Flash loan callback identifier
    bytes32 private constant FLASH_LOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    
    // Price feeds for token pairs
    mapping(address => address) private s_priceFeeds;


    // ============ Events ============
    event ArbitrageExecuted(
        address indexed tokenBorrow,
        address indexed tokenTarget,
        uint256 flashLoanAmount,
        uint256 grossProfit,
        uint256 netProfit,
        uint256 gasUsed
    );
    
    event ArbitrageFailed(
        address indexed tokenBorrow,
        address indexed tokenTarget,
        uint256 flashLoanAmount,
        string reason
    );
    
    event ConfigUpdated(string parameter, uint256 oldValue, uint256 newValue);
    event CircuitBreakerTriggered(bool isActive);
    event PriceFeedSet(address indexed token, address indexed priceFeed);
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);



    // ============ Constructor ============
    /**
     * @notice Initialize the arbitrage bot with required protocol addresses and parameters
     * @param balancerVault Address of Balancer Vault for flash loans
     * @param uniswapRouter Address of Uniswap V3 Swap Router
     * @param pancakeRouter Address of PancakeSwap Router
     * @param minProfitThreshold Minimum profit required to execute a trade (in wei)
     * @dev All addresses must be valid and non-zero
     */
    constructor(
        address balancerVault,
        address uniswapRouter,
        address pancakeRouter,
        uint256 minProfitThreshold
    ) Ownable(msg.sender) {
        // Validate addresses to prevent zero address errors
        if (balancerVault == address(0) || 
            uniswapRouter == address(0) || 
            pancakeRouter == address(0)) {
            revert ArbitrageBot__InvalidAddress();
        }
        
        i_balancerVault = balancerVault;
        i_uniswapRouter = uniswapRouter;
        i_pancakeRouter = pancakeRouter;
        s_minProfitThreshold = minProfitThreshold;
    }


    // ============ External Functions ============
    /**
     * @notice Execute an arbitrage opportunity between Uniswap V3 and PancakeSwap
     * @param tokenBorrow Token to borrow using flash loan
     * @param tokenTarget Token to swap to and from
     * @param amount Amount of tokenBorrow to flash loan
     * @param uniswapPoolFee Uniswap V3 pool fee 
     * @param uniToPancake Direction flag (true: Uni->Pancake, false: Pancake->Uni)
     * @dev Only callable by owner to prevent unauthorized transactions
     * @dev Reverts if contract paused or gas price too high
     */

    function executeArbitrage(
        address tokenBorrow,
        address tokenTarget,
        uint256 amount,
        uint24 uniswapPoolFee,
        bool uniToPancake
    ) external onlyOwner nonReentrant {
        // Check if contract is active
        if (!s_isActive) {
            revert ArbitrageBot__ContractPaused();
        }
        
        // Check if gas price is acceptable
        if (tx.gasprice > s_maxGasPrice) {
            revert ArbitrageBot__AbnormalPriceDetected();
        }
        
        // Validate token pair
        if (tokenBorrow == address(0) || tokenTarget == address(0) || tokenBorrow == tokenTarget) {
            revert ArbitrageBot__InvalidTokenPair();
        }
        
        // Prepare flash loan parameters
        address[] memory tokens = new address[](1);
        tokens[0] = tokenBorrow;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        
        // Encode arbitrage parameters for the flash loan callback
        bytes memory userData = abi.encode(
            ArbitrageParams({
                tokenBorrow: tokenBorrow,
                tokenTarget: tokenTarget,
                amount: amount,
                uniswapPoolFee: uniswapPoolFee,
                uniToPancake: uniToPancake
            })
        );
        
        // Execute flash loan from Balancer
        try IBalancerVault(i_balancerVault).flashLoan(
            address(this),
            tokens,
            amounts,
            userData
        ) {
            // Flash loan successful, arbitrage completed in the callback
        } catch (bytes memory reason) {
            // Log error if flash loan fails
            emit ArbitrageFailed(tokenBorrow, tokenTarget, amount, string(reason));
            revert ArbitrageBot__FlashLoanFailed();
        }
    }


    /**
     * @notice Balancer flash loan callback function
     * @dev Called by Balancer Vault after funds are borrowed
     * @param tokens Array of token addresses that were borrowed
     * @param amounts Array of amounts that were borrowed
     * @param feeAmounts Array of fee amounts to be paid
     * @param userData Encoded data passed from executeArbitrage
     * @return Success selector to acknowledge successful loan completion
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external returns (bytes32) {
        // Only Balancer Vault can call this function
        if (msg.sender != i_balancerVault) {
            revert ArbitrageBot__Unauthorized();
        }
        
        // Decode the parameters
        ArbitrageParams memory params = abi.decode(userData, (ArbitrageParams));
        
        // Validate that received token matches expected
        if (tokens[0] != params.tokenBorrow) {
            revert ArbitrageBot__InvalidTokenPair();
        }
        
        // Record starting gas for profit calculation
        uint256 startingGas = gasleft();
        
        // Amounts
        uint256 flashLoanAmount = amounts[0];
        uint256 flashLoanFee = feeAmounts[0];
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        
        // Initial balance of the borrowed token
        uint256 initialBalance = IERC20(params.tokenBorrow).balanceOf(address(this));
        
        // Execute the arbitrage based on direction
        if (params.uniToPancake) {
            // Step 1: Swap on Uniswap V3 (tokenBorrow -> tokenTarget)
            _swapOnUniswap(
                params.tokenBorrow,
                params.tokenTarget,
                flashLoanAmount,
                params.uniswapPoolFee
            );
            
            // Get the amount of tokenTarget received
            uint256 tokenTargetAmount = IERC20(params.tokenTarget).balanceOf(address(this));
            
            // Step 2: Swap on PancakeSwap (tokenTarget -> tokenBorrow)
            _swapOnPancakeSwap(
                params.tokenTarget,
                params.tokenBorrow,
                tokenTargetAmount
            );
        } else {
            // Step 1: Swap on PancakeSwap (tokenBorrow -> tokenTarget)
            _swapOnPancakeSwap(
                params.tokenBorrow,
                params.tokenTarget,
                flashLoanAmount
            );
            
            // Get the amount of tokenTarget received
            uint256 tokenTargetAmount = IERC20(params.tokenTarget).balanceOf(address(this));
            
            // Step 2: Swap on Uniswap V3 (tokenTarget -> tokenBorrow)
            _swapOnUniswap(
                params.tokenTarget,
                params.tokenBorrow,
                tokenTargetAmount,
                params.uniswapPoolFee
            );
        }
        
        // Final balance after arbitrage
        uint256 finalBalance = IERC20(params.tokenBorrow).balanceOf(address(this));
        
        // Calculate profit
        uint256 grossProfit = 0;
        if (finalBalance > initialBalance) {
            grossProfit = finalBalance - initialBalance;
        }
        
        // Ensure we have enough to repay the flash loan
        if (finalBalance < repayAmount) {
            revert ArbitrageBot__InsufficientFundsForRepayment(finalBalance, repayAmount);
        }
        
        // Calculate gas cost (approximation)
        uint256 gasUsed = startingGas - gasleft();
        uint256 gasCost = gasUsed * tx.gasprice;
        
        // Calculate net profit
        uint256 netProfit = grossProfit > gasCost ? grossProfit - gasCost : 0;
        
        // Check profit threshold
        if (netProfit < s_minProfitThreshold) {
            revert ArbitrageBot__ProfitBelowThreshold(netProfit, s_minProfitThreshold);
        }
        
        // Approve Balancer to take back the loan amount + fee
        IERC20(params.tokenBorrow).safeApprove(i_balancerVault, repayAmount);
        
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
            gasUsed
        );
        
        return FLASH_LOAN_CALLBACK_SUCCESS;
    }
}