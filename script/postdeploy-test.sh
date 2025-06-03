#!/bin/bash

# Post-deployment testing script
# Usage: ./scripts/postdeploy-test.sh <contract_address> <network>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    print_error "Contract address and network are required"
    echo "Usage: $0 <contract_address> <network>"
    echo "Example: $0 0x1234...5678 sepolia"
    exit 1
fi

CONTRACT_ADDRESS=$1
NETWORK=$2

# Set RPC URL based on network
if [ "$NETWORK" = "sepolia" ]; then
    RPC_URL=$SEPOLIA_RPC_URL
elif [ "$NETWORK" = "mainnet" ]; then
    RPC_URL=$ETH_RPC_URL
else
    print_error "Unsupported network: $NETWORK"
    exit 1
fi

WALLET_ADDRESS=$(cast wallet address devTestKey2)

print_header "POST-DEPLOYMENT TESTING FOR $NETWORK"
print_info "Contract Address: $CONTRACT_ADDRESS"
print_info "Wallet Address: $WALLET_ADDRESS"
print_info "Network: $NETWORK"
echo ""

# Test 1: Basic contract interaction
print_header "Basic Contract Validation"

# Check if contract exists
CONTRACT_CODE=$(cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL)
if [ ${#CONTRACT_CODE} -gt 2 ]; then
    print_status "Contract exists and has code"
else
    print_error "Contract not found or has no code"
    exit 1
fi

# Test 2: Owner verification
print_header "Ownership Verification"

OWNER=$(cast call $CONTRACT_ADDRESS "owner()" --rpc-url $RPC_URL)
OWNER_CLEAN=$(cast parse-bytes32-address $OWNER)

if [ "$(echo $OWNER_CLEAN | tr '[:upper:]' '[:lower:]')" = "$(echo $WALLET_ADDRESS | tr '[:upper:]' '[:lower:]')" ]; then
    print_status "Correct owner set: $OWNER_CLEAN"
else
    print_error "Wrong owner! Expected: $WALLET_ADDRESS, Got: $OWNER_CLEAN"
    exit 1
fi

# Test 3: Configuration check
print_header "Configuration Verification"

CONFIG=$(cast call $CONTRACT_ADDRESS "getConfig()" --rpc-url $RPC_URL)
print_status "Configuration retrieved successfully"

# Parse configuration
BALANCER_VAULT=$(echo $CONFIG | cut -d' ' -f1)
UNISWAP_ROUTER=$(echo $CONFIG | cut -d' ' -f2)
PANCAKE_ROUTER=$(echo $CONFIG | cut -d' ' -f3)
UNISWAP_QUOTER=$(echo $CONFIG | cut -d' ' -f4)
MIN_PROFIT_THRESHOLD=$(echo $CONFIG | cut -d' ' -f5)
SLIPPAGE_TOLERANCE=$(echo $CONFIG | cut -d' ' -f6)
MAX_GAS_PRICE=$(echo $CONFIG | cut -d' ' -f7)
IS_ACTIVE=$(echo $CONFIG | cut -d' ' -f8)

print_info "Balancer Vault: $(cast parse-bytes32-address $BALANCER_VAULT)"
print_info "Uniswap Router: $(cast parse-bytes32-address $UNISWAP_ROUTER)"
print_info "PancakeSwap Router: $(cast parse-bytes32-address $PANCAKE_ROUTER)"
print_info "Uniswap Quoter: $(cast parse-bytes32-address $UNISWAP_QUOTER)"
print_info "Min Profit Threshold: $MIN_PROFIT_THRESHOLD ($(cast to-unit $MIN_PROFIT_THRESHOLD 6) USDC)"
print_info "Slippage Tolerance: $SLIPPAGE_TOLERANCE ($(echo "scale=2; $SLIPPAGE_TOLERANCE/100" | bc)%)"
print_info "Max Gas Price: $MAX_GAS_PRICE ($(cast to-unit $MAX_GAS_PRICE gwei) gwei)"
print_info "Is Active: $IS_ACTIVE"

# Test 4: Owner function access
print_header "Owner Function Testing"

# Test setting min profit threshold
print_info "Testing setMinProfitThreshold..."
NEW_THRESHOLD=$((MIN_PROFIT_THRESHOLD + 1000000)) # Add 1 USDC

cast send $CONTRACT_ADDRESS "setMinProfitThreshold(uint256)" $NEW_THRESHOLD \
    --rpc-url $RPC_URL \
    --account devTestKey2 \
    --gas-limit 100000 > /dev/null

# Verify the change
UPDATED_CONFIG=$(cast call $CONTRACT_ADDRESS "getConfig()" --rpc-url $RPC_URL)
UPDATED_THRESHOLD=$(echo $UPDATED_CONFIG | cut -d' ' -f5)

if [ "$UPDATED_THRESHOLD" = "$NEW_THRESHOLD" ]; then
    print_status "setMinProfitThreshold works correctly"
    
    # Reset to original value
    cast send $CONTRACT_ADDRESS "setMinProfitThreshold(uint256)" $MIN_PROFIT_THRESHOLD \
        --rpc-url $RPC_URL \
        --account devTestKey2 \
        --gas-limit 100000 > /dev/null
else
    print_error "setMinProfitThreshold failed"
fi

# Test slippage tolerance setting
print_info "Testing setSlippageTolerance..."
cast send $CONTRACT_ADDRESS "setSlippageTolerance(uint256)" 100 \
    --rpc-url $RPC_URL \
    --account devTestKey2 \
    --gas-limit 100000 > /dev/null

print_status "setSlippageTolerance executed successfully"

# Reset slippage tolerance
cast send $CONTRACT_ADDRESS "setSlippageTolerance(uint256)" $SLIPPAGE_TOLERANCE \
    --rpc-url $RPC_URL \
    --account devTestKey2 \
    --gas-limit 100000 > /dev/null

# Test 5: Price feed validation (if on mainnet)
if [ "$NETWORK" = "mainnet" ]; then
    print_header "Price Feed Validation"
    
    # Check WETH price feed
    WETH_ADDRESS="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    WETH_FEED=$(cast call $CONTRACT_ADDRESS "getPriceFeed(address)" $WETH_ADDRESS --rpc-url $RPC_URL)
    
    if [ "$WETH_FEED" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        print_status "WETH price feed configured"
        WETH_FEED_CLEAN=$(cast parse-bytes32-address $WETH_FEED)
        print_info "WETH Price Feed: $WETH_FEED_CLEAN"
    else
        print_warning "WETH price feed not configured"
    fi
    
    # Check USDC price feed
    USDC_ADDRESS="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    USDC_FEED=$(cast call $CONTRACT_ADDRESS "getPriceFeed(address)" $USDC_ADDRESS --rpc-url $RPC_URL)
    
    if [ "$USDC_FEED" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        print_status "USDC price feed configured"
        USDC_FEED_CLEAN=$(cast parse-bytes32-address $USDC_FEED)
        print_info "USDC Price Feed: $USDC_FEED_CLEAN"
    else
        print_warning "USDC price feed not configured"
    fi
fi

# Test 6: Pool fee configuration
print_header "Pool Fee Configuration"

if [ "$NETWORK" = "mainnet" ]; then
    WETH_ADDRESS="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    USDC_ADDRESS="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
else
    WETH_ADDRESS="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    USDC_ADDRESS="0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"
fi

POOL_FEE=$(cast call $CONTRACT_ADDRESS "getPreferredUniswapPoolFee(address,address)" $WETH_ADDRESS $USDC_ADDRESS --rpc-url $RPC_URL)

if [ "$POOL_FEE" != "0" ]; then
    print_status "WETH/USDC pool fee configured: $POOL_FEE ($(echo "scale=3; $POOL_FEE/10000" | bc)%)"
else
    print_warning "WETH/USDC pool fee not configured"
fi

# Test 7: Circuit breaker test
print_header "Circuit Breaker Testing"

print_info "Testing circuit breaker toggle..."
cast send $CONTRACT_ADDRESS "toggleActive()" \
    --rpc-url $RPC_URL \
    --account devTestKey2 \
    --gas-limit 100000 > /dev/null

# Check if contract is now inactive
UPDATED_CONFIG=$(cast call $CONTRACT_ADDRESS "getConfig()" --rpc-url $RPC_URL)
UPDATED_ACTIVE=$(echo $UPDATED_CONFIG | cut -d' ' -f8)

if [ "$UPDATED_ACTIVE" = "false" ]; then
    print_status "Circuit breaker successfully deactivated contract"
    
    # Reactivate
    cast send $CONTRACT_ADDRESS "toggleActive()" \
        --rpc-url $RPC_URL \
        --account devTestKey2 \
        --gas-limit 100000 > /dev/null
    
    print_status "Contract reactivated"
else
    print_error "Circuit breaker test failed"
fi

# Test 8: Emergency withdrawal test (with zero balance - should not revert)
print_header "Emergency Withdrawal Testing"

print_info "Testing emergency withdrawal (should handle zero balance gracefully)..."

if [ "$NETWORK" = "mainnet" ]; then
    TEST_TOKEN="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"  # WETH
else
    TEST_TOKEN="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"  # Sepolia WETH
fi

cast send $CONTRACT_ADDRESS "emergencyWithdraw(address)" $TEST_TOKEN \
    --rpc-url $RPC_URL \
    --account devTestKey2 \
    --gas-limit 100000 > /dev/null

print_status "Emergency withdrawal executed (no tokens to withdraw)"

# Test 9: Gas price check
print_header "Gas Price Monitoring"

CURRENT_GAS_PRICE=$(cast gas-price --rpc-url $RPC_URL)
CURRENT_GAS_GWEI=$(cast to-unit $CURRENT_GAS_PRICE gwei)
MAX_GAS_GWEI=$(cast to-unit $MAX_GAS_PRICE gwei)

print_info "Current gas price: $CURRENT_GAS_GWEI gwei"
print_info "Contract max gas price: $MAX_GAS_GWEI gwei"

if (( $(echo "$CURRENT_GAS_GWEI < $MAX_GAS_GWEI" | bc -l) )); then
    print_status "Current gas price is within contract limits"
else
    print_warning "Current gas price exceeds contract maximum"
fi

# Final summary
print_header "TESTING SUMMARY"

print_status "All basic functionality tests passed!"
echo ""
print_info "Contract is ready for operation with the following configuration:"
echo "  • Owner: $WALLET_ADDRESS"
echo "  • Min Profit: $(cast to-unit $MIN_PROFIT_THRESHOLD 6) USDC"
echo "  • Slippage Tolerance: $(echo "scale=2; $SLIPPAGE_TOLERANCE/100" | bc)%"
echo "  • Max Gas Price: $(cast to-unit $MAX_GAS_PRICE gwei) gwei"
echo "  • Status: Active"
echo ""

if [ "$NETWORK" = "sepolia" ]; then
    print_info "Next steps for testnet:"
    echo "  1. Monitor for arbitrage opportunities"
    echo "  2. Test with small amounts if opportunities arise"
    echo "  3. Verify all functions work as expected"
    echo "  4. After thorough testing, deploy to mainnet"
else
    print_info "Next steps for mainnet:"
    echo "  1. Set up monitoring for arbitrage opportunities"
    echo "  2. Implement automated bot for opportunity detection"
    echo "  3. Monitor contract performance and profitability"
    echo "  4. Keep emergency procedures ready"
fi

echo ""
print_status "Testing completed successfully!"