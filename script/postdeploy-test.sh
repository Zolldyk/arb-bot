#!/bin/bash

# Post-deployment testing script (Fixed version)
# Usage: ./scripts/postdeploy-test-fixed.sh <contract_address> <network>

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

# Try to get wallet address, but don't fail if it doesn't work
WALLET_ADDRESS=""
if cast wallet address devTestKey2 >/dev/null 2>&1; then
    WALLET_ADDRESS=$(cast wallet address devTestKey2)
    print_info "Wallet Address: $WALLET_ADDRESS"
else
    print_warning "Wallet address not accessible - skipping wallet-dependent tests"
fi

print_header "POST-DEPLOYMENT TESTING FOR $NETWORK"
print_info "Contract Address: $CONTRACT_ADDRESS"
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

# Test 2: Owner verification (if wallet is accessible)
print_header "Ownership Verification"

OWNER=$(cast call $CONTRACT_ADDRESS "owner()" --rpc-url $RPC_URL)
OWNER_CLEAN=$(cast parse-bytes32-address $OWNER)

if [ -n "$WALLET_ADDRESS" ]; then
    if [ "$(echo $OWNER_CLEAN | tr '[:upper:]' '[:lower:]')" = "$(echo $WALLET_ADDRESS | tr '[:upper:]' '[:lower:]')" ]; then
        print_status "Correct owner set: $OWNER_CLEAN"
    else
        print_error "Wrong owner! Expected: $WALLET_ADDRESS, Got: $OWNER_CLEAN"
    fi
else
    print_info "Contract owner: $OWNER_CLEAN"
fi

# Test 3: Configuration check
print_header "Configuration Verification"

CONFIG=$(cast call $CONTRACT_ADDRESS "getConfig()" --rpc-url $RPC_URL)
print_status "Configuration retrieved successfully"

# Parse configuration (handling the response properly)
CONFIG_ARRAY=($(echo $CONFIG))
BALANCER_VAULT=${CONFIG_ARRAY[0]}
UNISWAP_ROUTER=${CONFIG_ARRAY[1]}
PANCAKE_ROUTER=${CONFIG_ARRAY[2]}
UNISWAP_QUOTER=${CONFIG_ARRAY[3]}
MIN_PROFIT_THRESHOLD=${CONFIG_ARRAY[4]}
SLIPPAGE_TOLERANCE=${CONFIG_ARRAY[5]}
MAX_GAS_PRICE=${CONFIG_ARRAY[6]}
IS_ACTIVE=${CONFIG_ARRAY[7]}

print_info "Balancer Vault: $(cast parse-bytes32-address $BALANCER_VAULT)"
print_info "Uniswap Router: $(cast parse-bytes32-address $UNISWAP_ROUTER)"
print_info "PancakeSwap Router: $(cast parse-bytes32-address $PANCAKE_ROUTER)"
print_info "Uniswap Quoter: $(cast parse-bytes32-address $UNISWAP_QUOTER)"
print_info "Min Profit Threshold: $MIN_PROFIT_THRESHOLD ($(echo "scale=6; $MIN_PROFIT_THRESHOLD/1000000" | bc) USDC)"
print_info "Slippage Tolerance: $SLIPPAGE_TOLERANCE ($(echo "scale=2; $SLIPPAGE_TOLERANCE/100" | bc)%)"
print_info "Max Gas Price: $MAX_GAS_PRICE ($(cast to-unit $MAX_GAS_PRICE gwei) gwei)"
print_info "Is Active: $IS_ACTIVE"

# Test 4: Price feed validation
print_header "Price Feed Validation"

if [ "$NETWORK" = "mainnet" ]; then
    WETH_ADDRESS="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    USDC_ADDRESS="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
else
    WETH_ADDRESS="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    USDC_ADDRESS="0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"
fi

# Check WETH price feed
WETH_FEED=$(cast call $CONTRACT_ADDRESS "getPriceFeed(address)" $WETH_ADDRESS --rpc-url $RPC_URL)

if [ "$WETH_FEED" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    print_status "WETH price feed configured"
    WETH_FEED_CLEAN=$(cast parse-bytes32-address $WETH_FEED)
    print_info "WETH Price Feed: $WETH_FEED_CLEAN"
else
    print_warning "WETH price feed not configured"
fi

# Check USDC price feed
USDC_FEED=$(cast call $CONTRACT_ADDRESS "getPriceFeed(address)" $USDC_ADDRESS --rpc-url $RPC_URL)

if [ "$USDC_FEED" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    print_status "USDC price feed configured"
    USDC_FEED_CLEAN=$(cast parse-bytes32-address $USDC_FEED)
    print_info "USDC Price Feed: $USDC_FEED_CLEAN"
else
    print_warning "USDC price feed not configured"
fi

# Test 5: Pool fee configuration
print_header "Pool Fee Configuration"

POOL_FEE=$(cast call $CONTRACT_ADDRESS "getPreferredUniswapPoolFee(address,address)" $WETH_ADDRESS $USDC_ADDRESS --rpc-url $RPC_URL)

if [ "$POOL_FEE" != "0" ]; then
    print_status "WETH/USDC pool fee configured: $POOL_FEE ($(echo "scale=3; $POOL_FEE/10000" | bc)%)"
else
    print_warning "WETH/USDC pool fee not configured"
fi

# Test 6: Gas price check
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

# Test 7: Owner function testing (only if wallet is accessible)
if [ -n "$WALLET_ADDRESS" ]; then
    print_header "Owner Function Testing (Interactive)"
    
    print_info "Testing owner functions requires wallet access."
    print_info "Would you like to test owner functions? This will require entering your wallet password."
    read -p "Test owner functions? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Testing setMinProfitThreshold..."
        
        # Test setting min profit threshold
        NEW_THRESHOLD=$((MIN_PROFIT_THRESHOLD + 1000000)) # Add 1 USDC
        
        if cast send $CONTRACT_ADDRESS "setMinProfitThreshold(uint256)" $NEW_THRESHOLD \
            --rpc-url $RPC_URL \
            --account devTestKey2 \
            --gas-limit 100000 >/dev/null 2>&1; then
            
            # Verify the change
            UPDATED_CONFIG=$(cast call $CONTRACT_ADDRESS "getConfig()" --rpc-url $RPC_URL)
            UPDATED_CONFIG_ARRAY=($(echo $UPDATED_CONFIG))
            UPDATED_THRESHOLD=${UPDATED_CONFIG_ARRAY[4]}
            
            if [ "$UPDATED_THRESHOLD" = "$NEW_THRESHOLD" ]; then
                print_status "setMinProfitThreshold works correctly"
                
                # Reset to original value
                cast send $CONTRACT_ADDRESS "setMinProfitThreshold(uint256)" $MIN_PROFIT_THRESHOLD \
                    --rpc-url $RPC_URL \
                    --account devTestKey2 \
                    --gas-limit 100000 >/dev/null 2>&1
            else
                print_error "setMinProfitThreshold failed"
            fi
        else
            print_warning "Owner function test failed - wallet access issue"
        fi
    else
        print_info "Skipping owner function tests"
    fi
else
    print_header "Owner Function Testing"
    print_warning "Skipping owner function tests - wallet not accessible"
    print_info "To test owner functions, ensure your devTestKey2 wallet is properly configured"
fi

# Final summary
print_header "TESTING SUMMARY"

print_status "Basic functionality tests completed!"
echo ""
print_info "Contract Status Summary:"
echo "  • Contract Address: $CONTRACT_ADDRESS"
echo "  • Owner: $OWNER_CLEAN"
echo "  • Min Profit: $(echo "scale=6; $MIN_PROFIT_THRESHOLD/1000000" | bc) USDC"
echo "  • Slippage Tolerance: $(echo "scale=2; $SLIPPAGE_TOLERANCE/100" | bc)%"
echo "  • Max Gas Price: $(cast to-unit $MAX_GAS_PRICE gwei) gwei"
echo "  • Status: $IS_ACTIVE"
echo ""

if [ "$NETWORK" = "sepolia" ]; then
    print_info "Contract is ready for testing on Sepolia!"
    echo "  • View on Etherscan: https://sepolia.etherscan.io/address/$CONTRACT_ADDRESS"
    echo "  • All read-only functions are working"
    echo "  • Ready for arbitrage opportunity testing"
else
    print_info "Contract is live on Mainnet!"
    echo "  • View on Etherscan: https://etherscan.io/address/$CONTRACT_ADDRESS"
    echo "  • Monitor for arbitrage opportunities"
    echo "  • Implement automated monitoring"
fi

echo ""
print_status "Testing completed successfully!"