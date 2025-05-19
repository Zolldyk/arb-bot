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
    // Fee for flash loans (0.09%)
    uint256 public constant FLASH_LOAN_FEE_PERCENTAGE = 9 * 1e15; // 0.09% = 9/10000 = 9*10^15/10^18

    // Function to simulate a flash loan
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external
    {
        require(tokens.length == amounts.length, "Length mismatch");

        // For each token, send the requested amount to the recipient
        for (uint256 i = 0; i < tokens.length; i++) {
            // Calculate flash loan fee
            uint256 feeAmount = (amounts[i] * FLASH_LOAN_FEE_PERCENTAGE) / 1e18;
            uint256[] memory feeAmounts = new uint256[](tokens.length);
            feeAmounts[i] = feeAmount;

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

            // Verify the flash loan has been repaid (amount + fee)
            require(
                IERC20(tokens[i]).transferFrom(recipient, address(this), amounts[i] + feeAmount),
                "Flash loan not repaid"
            );
        }
    }
}
