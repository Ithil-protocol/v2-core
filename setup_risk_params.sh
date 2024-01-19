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
RPC_URL="http://localhost:8545" # "https://arb-mainnet..."
SERVICE_ADDRESS="0x00000"

# Tokens
USDC=0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
USDT=0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
DAI=0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
FRAX=0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F
WETH=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
WBTC=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f

cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $USDC 1 1 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $USDT 1 1 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $DAI 1 1 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $FRAX 1 1 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $WBTC 1 1 1
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $SERVICE_ADDRESS "setRiskParams(address,uint256,uint256,uint256)" $WETH 1 1 1
