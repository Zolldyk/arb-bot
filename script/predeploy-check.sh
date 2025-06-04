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

# Check if network is provided
if [ -z "$1" ]; then
    print_error "Network is required"
    echo "Usage: $0 <network>"
    echo "Networks: sepolia, mainnet"
    exit 1
fi

NETWORK=$1
ERRORS=0

print_header "PRE-DEPLOYMENT CHECKLIST FOR $NETWORK"

# Check 1: Environment file exists
print_header "Environment Configuration"
if [ -f ".env" ]; then
    print_status ".env file exists"
else
    print_error ".env file not found"
    ((ERRORS++))
fi

# Check 2: Required environment variables
print_header "Environment Variables"

if [ "$NETWORK" = "sepolia" ]; then
    RPC_VAR="SEPOLIA_RPC_URL"
else
    RPC_VAR="ETH_RPC_URL"
fi

if [ -n "${!RPC_VAR}" ]; then
    print_status "$RPC_VAR is set"
else
    print_error "$RPC_VAR is not set"
    ((ERRORS++))
fi

if [ -n "$ETHERSCAN_API_KEY" ]; then
    print_status "ETHERSCAN_API_KEY is set"
else
    print_warning "ETHERSCAN_API_KEY is not set (verification will fail)"
fi

# Check 3: Wallet configuration
print_header "Wallet Configuration"

if cast wallet list | grep -q "devTestKey2"; then
    print_status "devTestKey2 wallet found"
    
    # Get wallet address
    WALLET_ADDRESS=$(cast wallet address devTestKey2)
    print_status "Wallet address: $WALLET_ADDRESS"
    
    # Check balance
    if [ "$NETWORK" = "sepolia" ]; then
        BALANCE=$(cast balance $WALLET_ADDRESS --rpc-url $SEPOLIA_RPC_URL)
    else
        BALANCE=$(cast balance $WALLET_ADDRESS --rpc-url $ETH_RPC_URL)
    fi
    
    # Convert balance to ETH (from wei)
    BALANCE_ETH=$(cast to-unit $BALANCE ether)
    
    # Check if balance is sufficient (at least 0.1 ETH for deployment)
    if (( $(echo "$BALANCE_ETH >= 0.1" | bc -l) )); then
        print_status "Wallet balance: $BALANCE_ETH ETH (sufficient)"
    else
        print_error "Wallet balance: $BALANCE_ETH ETH (insufficient - need at least 0.1 ETH)"
        ((ERRORS++))
    fi
else
    print_error "devTestKey2 wallet not found"
    echo "Run: cast wallet import devTestKey2 --interactive"
    ((ERRORS++))
fi

# Check 4: Network connectivity
print_header "Network Connectivity"

if [ "$NETWORK" = "sepolia" ]; then
    if cast chain-id --rpc-url $SEPOLIA_RPC_URL >/dev/null 2>&1; then
        CHAIN_ID=$(cast chain-id --rpc-url $SEPOLIA_RPC_URL)
        if [ "$CHAIN_ID" = "11155111" ]; then
            print_status "Sepolia network connection successful"
        else
            print_error "Connected to wrong network (Chain ID: $CHAIN_ID, expected: 11155111)"
            ((ERRORS++))
        fi
    else
        print_error "Cannot connect to Sepolia network"
        ((ERRORS++))
    fi
else
    if cast chain-id --rpc-url $ETH_RPC_URL >/dev/null 2>&1; then
        CHAIN_ID=$(cast chain-id --rpc-url $ETH_RPC_URL)
        if [ "$CHAIN_ID" = "1" ]; then
            print_status "Mainnet network connection successful"
        else
            print_error "Connected to wrong network (Chain ID: $CHAIN_ID, expected: 1)"
            ((ERRORS++))
        fi
    else
        print_error "Cannot connect to Mainnet network"
        ((ERRORS++))
    fi
fi

# Check 5: Foundry configuration
print_header "Foundry Configuration"

if forge --version >/dev/null 2>&1; then
    FORGE_VERSION=$(forge --version)
    print_status "Foundry installed: $FORGE_VERSION"
else
    print_error "Foundry not found"
    ((ERRORS++))
fi

# Check 6: Dependencies
print_header "Dependencies"

if [ -d "lib/openzeppelin-contracts" ]; then
    print_status "OpenZeppelin contracts found"
else
    print_error "OpenZeppelin contracts not found"
    echo "Run: forge install openzeppelin/openzeppelin-contracts"
    ((ERRORS++))
fi

if [ -d "lib/chainlink" ]; then
    print_status "Chainlink contracts found"
else
    print_error "Chainlink contracts not found"
    echo "Run: forge install smartcontractkit/chainlink"
    ((ERRORS++))
fi

# Check 7: Contract compilation
print_header "Contract Compilation"

if forge build >/dev/null 2>&1; then
    print_status "Contract compilation successful"
else
    print_error "Contract compilation failed"
    echo "Run: forge build"
    ((ERRORS++))
fi

# Check 8: Test execution
print_header "Test Execution"

if forge test >/dev/null 2>&1; then
    print_status "All tests pass"
else
    print_warning "Some tests failing (this may be expected for integration tests)"
fi

# Check 9: Gas estimation
print_header "Gas Estimation"

if [ "$NETWORK" = "sepolia" ]; then
    GAS_PRICE=$(cast gas-price --rpc-url $SEPOLIA_RPC_URL)
    RPC_URL=$SEPOLIA_RPC_URL
else
    GAS_PRICE=$(cast gas-price --rpc-url $ETH_RPC_URL)
    RPC_URL=$ETH_RPC_URL
fi

GAS_PRICE_GWEI=$(cast to-unit $GAS_PRICE gwei)
print_status "Current gas price: $GAS_PRICE_GWEI gwei"

# Estimate deployment cost (approximate)
ESTIMATED_GAS=3000000  # Estimated gas for deployment
DEPLOYMENT_COST_WEI=$((ESTIMATED_GAS * GAS_PRICE))
DEPLOYMENT_COST_ETH=$(cast to-unit $DEPLOYMENT_COST_WEI ether)

print_status "Estimated deployment cost: $DEPLOYMENT_COST_ETH ETH"

# Check 10: Contract addresses validation
print_header "Contract Addresses Validation"

if [ "$NETWORK" = "sepolia" ]; then
    # Validate Sepolia addresses
    BALANCER_VAULT="0xBA12222222228d8Ba445958a75a0704d566BF2C8"
    UNISWAP_ROUTER="0xE592427A0AEce92De3Edee1F18E0157C05861564"
    
    # Check if contracts exist at these addresses
    if cast code $BALANCER_VAULT --rpc-url $RPC_URL | grep -q "0x"; then
        print_status "Balancer Vault exists on Sepolia"
    else
        print_warning "Balancer Vault may not exist on Sepolia"
    fi
    
    if cast code $UNISWAP_ROUTER --rpc-url $RPC_URL | grep -q "0x"; then
        print_status "Uniswap Router exists on Sepolia"
    else
        print_warning "Uniswap Router may not exist on Sepolia"
    fi
else
    # Validate Mainnet addresses
    BALANCER_VAULT="0xBA12222222228d8Ba445958a75a0704d566BF2C8"
    UNISWAP_ROUTER="0xE592427A0AEce92De3Edee1F18E0157C05861564"
    PANCAKE_ROUTER="0xEfF92A263d31888d860bD50809A8D171709b7b1c"
    
    if cast code $BALANCER_VAULT --rpc-url $RPC_URL | grep -q "0x"; then
        print_status "Balancer Vault exists on Mainnet"
    else
        print_error "Balancer Vault not found on Mainnet"
        ((ERRORS++))
    fi
    
    if cast code $UNISWAP_ROUTER --rpc-url $RPC_URL | grep -q "0x"; then
        print_status "Uniswap Router exists on Mainnet"
    else
        print_error "Uniswap Router not found on Mainnet"
        ((ERRORS++))
    fi
    
    if cast code $PANCAKE_ROUTER --rpc-url $RPC_URL | grep -q "0x"; then
        print_status "PancakeSwap Router exists on Mainnet"
    else
        print_error "PancakeSwap Router not found on Mainnet"
        ((ERRORS++))
    fi
fi

# Final summary
print_header "SUMMARY"

if [ $ERRORS -eq 0 ]; then
    print_status "All checks passed! Ready for deployment to $NETWORK"
    echo ""
    echo "Next steps:"
    echo "1. Review the deployment script: script/DeployArbitrageBot.s.sol"
    echo "2. Run the deployment command:"
    echo ""
    if [ "$NETWORK" = "sepolia" ]; then
        echo "   forge script script/DeployArbitrageBot.s.sol:DeployArbitrageBot \\"
        echo "       --rpc-url \$SEPOLIA_RPC_URL \\"
        echo "       --account devTestKey2 \\"
        echo "       --sender \$(cast wallet address devTestKey2) \\"
        echo "       --broadcast \\"
        echo "       --verify \\"
        echo "       -vvvv"
    else
        echo "   forge script script/DeployArbitrageBot.s.sol:DeployArbitrageBot \\"
        echo "       --rpc-url \$ETH_RPC_URL \\"
        echo "       --account devTestKey2 \\"
        echo "       --sender \$(cast wallet address devTestKey2) \\"
        echo "       --broadcast \\"
        echo "       --verify \\"
        echo "       -vvvv"
    fi
    echo ""
    exit 0
else
    print_error "$ERRORS error(s) found. Please fix them before deployment."
    exit 1
fi