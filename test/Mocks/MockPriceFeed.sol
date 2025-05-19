// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockPriceFeed
 * @notice Mock implementation of Chainlink price feed for testing
 * @dev Implements the AggregatorV3Interface with configurable price data
 */
contract MockPriceFeed is AggregatorV3Interface {
    // Price data
    int256 private _price;
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    uint80 _getRoundData;
    uint80 _latestRoundData;

    /**
     * @notice Constructor for mock price feed
     * @param price Initial price value
     * @param decimalsValue Decimals for price feed (typically 8 for Chainlink)
     * @param descriptionValue Description of the price feed
     */
    constructor(int256 price, uint8 decimalsValue, string memory descriptionValue) {
        _price = price;
        _decimals = decimalsValue;
        _description = descriptionValue;
        _version = 1;
    }

    /**
     * @notice Set the price for the feed
     * @param price New price value
     */
    function setPrice(int256 price) external {
        _price = price;
    }

    /**
     * @notice Get the number of decimals for the price feed
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Get the description of the price feed
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    /**
     * @notice Get the version of the price feed
     */
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @notice Get the latest round data
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            1, // roundId
            _price, // answer
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            _roundId, // roundId
            _price, // answer
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            _roundId // answeredInRound
        );
    }
}
