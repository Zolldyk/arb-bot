// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IBalancerFLashLoan {
    /**
     * @dev Perform a flash loan
     * @param tokens The tokens to be flash-borrowed
     * @param amounts The amounts of tokens to be flash-borrowed
     * @param userData User data to be passed to the flash loan callback
     */

    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}