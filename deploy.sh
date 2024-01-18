#!/bin/bash

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "Error: DEPLOYER_PRIVATE_KEY is not set."
    exit 1
fi

if [ -z "$DEPLOYER_PUBLIC_KEY" ]; then
    echo "Error: DEPLOYER_PUBLIC_KEY is not set."
    exit 1
fi

# Config
RPC_URL="http://localhost:8545"
CHAIN_NAME="arbitrum"
VERIFY=false
AAVE_DEADLINE=1
FRAX_DEADLINE=1
GMX_DEADLINE=1
FIXEDYIELD_DEADLINE=1
FIXEDYIELD_YELD=0

if [ "$VERIFY" = true ] && [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY is not set."
    exit 1
fi

# Tokens
USDC=0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
USDT=0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
DAI=0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
FRAX=0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F
WETH=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
WBTC=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
tokens=($USDC $USDT $DAI $FRAX $WETH $WBTC)

# Params
AAVE=0x794a61358D6845594F94dc1DB02A252b5b4814aD
FRAXLEND=0x2D0483FefAbA4325c7521539a3DFaCf94A19C472
GMXROUTER1=0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1
GMXROUTER2=0xB95DB5B167D75e6d04227CfFFA61069348d271F5

# Deploy Manager
echo "Deploying Manager contract..."
MANAGER=$(forge create src/Manager.sol:Manager --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize)
export MANAGER_ADDRESS=$(echo "$MANAGER" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$MANAGER_ADDRESS" ]; then
    echo "Error: Manager contract deployment failed"
    exit 1
fi

if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    forge verify-contract $MANAGER_ADDRESS src/Manager.sol:Manager --chain $CHAIN_NAME --watch
    echo "OK!"
fi

# Create vaults
declare -A VAULTS
echo "Creating vaults..."
for token in "${tokens[@]}"; do
    cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $token "approve(address,uint256)" $MANAGER_ADDRESS 1000
    cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "create(address)" $token
    VAULT_BYTES=$(cast call --rpc-url=$RPC_URL $MANAGER_ADDRESS "vaults(address)" $token)
    VAULT_ADDRESS="0x${VAULT_BYTES: -40}"    
    if [ "$VAULT_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
        echo "Error: Vault creation failed for token $token"
        exit 1
    fi
    echo "Vault for $token created at $VAULT_ADDRESS"
    if [ "$VERIFY" = true ]; then
        echo "Verifying Vault..."
        VAULTS[$token]=$VAULT_ADDRESS
        ENCODED_ARGS=$(cast abi-encode "constructor(address)" $token)
        forge verify-contract ${VAULTS[$token]} src/Vault.sol:Vault --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch
        echo "OK!"
    fi
done

# Deploy AaveService
echo "Deploying AaveService contract..."
AAVESERVICE=$(forge create src/services/debit/AaveService.sol:AaveService --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize --constructor-args $MANAGER_ADDRESS $AAVE $AAVE_DEADLINE)
AAVESERVICE_ADDRESS=$(echo "$AAVESERVICE" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$AAVESERVICE_ADDRESS" ]; then
    echo "Error: AaveService contract deployment failed"
    exit 1
fi
if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    ENCODED_ARGS=$(cast abi-encode "constructor(address,address,uint256)" $MANAGER_ADDRESS $AAVE $AAVE_DEADLINE)
    forge verify-contract $AAVESERVICE_ADDRESS src/services/debit/AaveService.sol:AaveService --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch
    echo "OK!"
fi

# Deploy FraxlendService
echo "Deploying FraxlendService contract..."
FRAXSERVICE=$(forge create src/services/debit/FraxlendService.sol:FraxlendService --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize --constructor-args $MANAGER_ADDRESS $FRAXLEND $FRAX_DEADLINE)
FRAXSERVICE_ADDRESS=$(echo "$FRAXSERVICE" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$FRAXSERVICE_ADDRESS" ]; then
    echo "Error: FraxlendService contract deployment failed"
    exit 1
fi
if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    ENCODED_ARGS=$(cast abi-encode "constructor(address,address,uint256)" $MANAGER_ADDRESS $FRAXLEND $FRAX_DEADLINE)
    forge verify-contract $FRAXSERVICE_ADDRESS src/services/debit/FraxlendService.sol:FraxlendService --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch
    echo "OK!"
fi

# Deploy GmxService
echo "Deploying GmxService contract..."
GMXSERVICE=$(forge create src/services/debit/GmxService.sol:GmxService --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize --constructor-args $MANAGER_ADDRESS $GMXROUTER1 $GMXROUTER2 $GMX_DEADLINE)
GMXSERVICE_ADDRESS=$(echo "$GMXSERVICE" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$GMXSERVICE_ADDRESS" ]; then
    echo "Error: GmxService contract deployment failed"
    exit 1
fi
if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    ENCODED_ARGS=$(cast abi-encode "constructor(address,address,address,uint256)" $MANAGER_ADDRESS $GMXROUTER1 $GMXROUTER2 $GMX_DEADLINE)
    forge verify-contract $GMXSERVICE_ADDRESS src/services/debit/GmxService.sol:GmxService --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch
    echo "OK!"
fi

# Deploy FixedYieldService
echo "Deploying FixedYieldService contract..."
FIXEDYIELD=$(forge create src/services/credit/FixedYieldService.sol:FixedYieldService --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --optimize --constructor-args $MANAGER_ADDRESS $FIXEDYIELD_YELD $FIXEDYIELD_DEADLINE)
FIXEDYIELD_ADDRESS=$(echo "$FIXEDYIELD" | grep "Deployed to:" | awk '{print $3}')
if [ -z "$FIXEDYIELD_ADDRESS" ]; then
    echo "Error: FixedYieldService contract deployment failed"
    exit 1
fi
if [ "$VERIFY" = true ]; then
    echo "Verifying..."
    ENCODED_ARGS=$(cast abi-encode "constructor(address,uint256,uint256,uint256)" $MANAGER_ADDRESS $FIXEDYIELD_YELD $FIXEDYIELD_DEADLINE)
    forge verify-contract $FIXEDYIELD_ADDRESS src/services/credit/FixedYieldService.sol:FixedYieldService --constructor-args $ENCODED_ARGS --chain $CHAIN_NAME --watch
    echo "OK!"
fi

# Set caps

## AaveService
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $USDC 800000000000000000 10000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $USDT 800000000000000000 10000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $DAI 800000000000000000 10000000000000000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $WETH 800000000000000000 4000000000000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $WBTC 800000000000000000 20000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $AAVESERVICE_ADDRESS $FRAX 800000000000000000 10000000000000000000000

## GmxService
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $USDC 500000000000000000 10000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $USDT 500000000000000000 10000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $DAI 500000000000000000 10000000000000000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $WETH 500000000000000000 4000000000000000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $WBTC 500000000000000000 20000000
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $GMXSERVICE_ADDRESS $FRAX 500000000000000000 10000000000000000000000

## FraxlendService
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $FRAXSERVICE_ADDRESS $FRAX 500000000000000000 10000000000000000000000

## FixedYieldService
for token in "${tokens[@]}"; do
    cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $MANAGER_ADDRESS "setCap(address,address,uint256,uint256)" $FIXEDYIELD_ADDRESS $token 1 0
done
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $USDC 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $USDT 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $DAI 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $WETH 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $WBTC 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $FIXEDYIELD_ADDRESS "setMinLoan(address,uint256)" $FRAX 1

# Print out address
echo " "
echo "---------------------------------------------------------------------------"
echo "Manager contract deployed to $MANAGER_ADDRESS"
for token in "${tokens[@]}"; do
    echo "Vault for $token deployed to $VAULTS[$token]"
done
echo "AaveService contract deployed to $AAVESERVICE_ADDRESS"
echo "FraxlendService contract deployed to $FRAXSERVICE_ADDRESS"
echo "GmxService contract deployed to $GMXSERVICE_ADDRESS"
echo "FixedYieldService contract deployed to $FIXEDYIELD_ADDRESS"
echo "---------------------------------------------------------------------------"
