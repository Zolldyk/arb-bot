// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IBalancerVault} from "../../src/Interfaces/IBalancerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockBalancerVault
 * @notice Mock contract for Balancer Vault to simulate flash loans
 * @dev Used for testing the flash loan functionality of the arbitrage bot
 */
contract MockBalancerVault {
    // Balancer flash loans are fee-free
    uint256 public constant FLASH_LOAN_FEE_PERCENTAGE = 0; // 0% fee for Balancer

    // Function to simulate a flash loan
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external
    {
        require(tokens.length == amounts.length, "Length mismatch");

        // For each token, send the requested amount to the recipient
        for (uint256 i = 0; i < tokens.length; i++) {
            // Balancer flash loans have zero fees
            uint256[] memory feeAmounts = new uint256[](tokens.length);
            feeAmounts[i] = 0; // No fee for Balancer flash loans

            // Transfer the tokens to the recipient (assuming we have them)
            // In a test environment, we'll use vm.deal to make sure this contract has enough
            IERC20(tokens[i]).transfer(recipient, amounts[i]);

            // Call receiveFlashLoan on the recipient
            // This is where the arbitrage logic would execute
            (bool success,) = recipient.call(
                abi.encodeWithSignature(
                    "receiveFlashLoan(address[],uint256[],uint256[],bytes)", tokens, amounts, feeAmounts, userData
                )
            );

            require(success, "Flash loan callback failed");

            // Verify the flash loan has been repaid (only the borrowed amount, no fee)
            require(IERC20(tokens[i]).transferFrom(recipient, address(this), amounts[i]), "Flash loan not repaid");
        }
    }
}
