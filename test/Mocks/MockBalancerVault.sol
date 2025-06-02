// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IBalancerVault, IFlashLoanRecipient} from "../../src/Interfaces/IBalancerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockBalancerVault
 * @notice FIXED Mock contract for Balancer Vault to simulate flash loans correctly
 * @dev Used for testing the flash loan functionality - now matches real Balancer behavior
 */
contract MockBalancerVault {
    // Balancer flash loans are fee-free (0%)
    uint256 public constant FLASH_LOAN_FEE_PERCENTAGE = 0;

    /**
     * @notice FIXED flash loan implementation that matches Balancer's actual behavior
     * @dev This implementation correctly checks for token balance increases instead of approvals
     */
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external {
        require(tokens.length == amounts.length, "Length mismatch");

        // Calculate fee amounts (0 for Balancer)
        uint256[] memory feeAmounts = new uint256[](tokens.length);
        uint256[] memory preLoanBalances = new uint256[](tokens.length);

        // Record pre-loan balances and transfer tokens to recipient
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);

            // Record balance before loan
            preLoanBalances[i] = token.balanceOf(address(this));

            // Set fee amount (0 for Balancer)
            feeAmounts[i] = 0;

            // Ensure we have enough tokens to lend
            require(preLoanBalances[i] >= amounts[i], "Insufficient balance for flash loan");

            // Transfer tokens to recipient
            require(token.transfer(address(recipient), amounts[i]), "Flash loan transfer failed");
        }

        // Call the recipient's flash loan callback
        recipient.receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        // CRITICAL: Check that tokens were transferred back (not just approved)
        // This is how real Balancer works - it checks balance increases
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 postLoanBalance = token.balanceOf(address(this));

            // Check that we received back at least the borrowed amount + fees
            uint256 expectedRepayment = amounts[i] + feeAmounts[i];
            require(postLoanBalance >= preLoanBalances[i], "Flash loan not repaid - tokens not transferred back");

            // For Balancer, since fees are 0, we just need the original amount back
            uint256 actualRepayment = postLoanBalance - preLoanBalances[i] + amounts[i];
            require(actualRepayment >= expectedRepayment, "Insufficient flash loan repayment");
        }
    }

    /**
     * @notice Helper function to fund the mock vault with tokens for testing
     */
    function fundVault(address token, uint256 amount) external {
        // This would typically be called in test setup to give the vault tokens to lend
        // In real Balancer, the vault holds user deposits
    }

    /**
     * @notice Get the balance of a specific token in this vault
     */
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
