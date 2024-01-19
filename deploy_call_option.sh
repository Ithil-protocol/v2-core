#!/bin/bash

# DEPLOYER_PRIVATE_KEY=0x...
# DEPLOYER_PUBLIC_KEY=0x...
# ETHERSCAN_API_KEY=...

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "Error: DEPLOYER_PRIVATE_KEY is not set."
    exit 1
fi

if [ -z "$DEPLOYER_PUBLIC_KEY" ]; then
    echo "Error: DEPLOYER_PUBLIC_KEY is not set."
    exit 1
fi

if [ "$VERIFY" = true ] && [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY is not set."
    exit 1
fi

# Config
RPC_URL="http://localhost:8545" # "https://arb-mainnet..."
CHAIN_NAME="sepolia" # "arbitrum" "mainnet"...
VERIFY=true
MANAGER_ADDRESS="0x000"
TOKEN="0x000"

# Deploy Manager
echo "Deploying Call Option contract..."
CALL_OPTION=$(forge create src/services/credit/CallOption.sol:CallOption --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize --constructor-args 1 1 1)
export CALL_OPTION_ADDRESS=$(echo "$CALL_OPTION" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$CALL_OPTION_ADDRESS" ]; then
    echo "Error: Call Option contract deployment failed"
    exit 1
fi

if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    ENCODED_ARGS=$(cast abi-encode "constructor(address,address,uint256,uint256,uint256,uint256,uint256,address)" $MANAGER_ADDRESS $AAVE $AAVE_DEADLINE)
    forge verify-contract $CALL_OPTION_ADDRESS src/services/credit/CallOption.sol:CallOption --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch --etherscan-api-key $ETHERSCAN_API_KEY
    echo "OK!"
fi

# Set cap
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $CALL_OPTION_ADDRESS $TOKEN 1 0

# Print out address
echo " "
echo "---------------------------------------------------------------------------"
echo "CallOption contract deployed to $CALL_OPTION_ADDRESS"
echo "---------------------------------------------------------------------------"
