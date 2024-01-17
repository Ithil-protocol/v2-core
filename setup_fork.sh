#!/bin/bash

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "Error: DEPLOYER_PRIVATE_KEY is not set."
    exit 1
fi

if [ -z "$DEPLOYER_PUBLIC_KEY" ]; then
    echo "Error: DEPLOYER_PUBLIC_KEY is not set."
    exit 1
fi

RPC_URL="http://localhost:8545"

# Tokens
USDC=0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
USDT=0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
DAI=0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
FRAX=0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F
WETH=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
WBTC=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
tokens=($USDC $USDT $DAI $FRAX $WETH $WBTC)

# Give tokens to user
BINANCE=0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D
USDC_WHALE=$BINANCE
USDT_WHALE=$BINANCE
WETH_WHALE=$BINANCE
WBTC_WHALE=0x7546966122E636A601a3eA4497d3509F160771d8
DAI_WHALE=0x2d070ed1321871841245D8EE5B84bD2712644322
FRAX_WHALE=0x9CBF099ff424979439dFBa03F00B5961784c06ce
for token in "${tokens[@]}"; do
    if [ "$token" == "$WETH" ]; then
        whale_address=$WETH_WHALE
    elif [ "$token" == "$WBTC" ]; then
        whale_address=$WBTC_WHALE
    elif [ "$token" == "$FRAX" ]; then
        whale_address=$FRAX_WHALE
    elif [ "$token" == "$DAI" ]; then
        whale_address=$DAI_WHALE
    elif [ "$token" == "$USDC" ]; then
        whale_address=$USDC_WHALE
    elif [ "$token" == "$USDT" ]; then
        whale_address=$USDT_WHALE
    else
        echo "Error: Unknown token $token"
        exit 1
    fi

    cast rpc anvil_impersonateAccount $whale_address --rpc-url=$RPC_URL > /dev/null 2>&1
    BALANCE=$(cast call --rpc-url=$RPC_URL $token "balanceOf(address)(uint256)" $whale_address)
    cast send $token --rpc-url=$RPC_URL --unlocked --from $whale_address "transfer(address,uint256)(bool)" $DEPLOYER_PUBLIC_KEY $BALANCE > /dev/null 2>&1
    cast rpc anvil_stopImpersonatingAccount $whale_address --rpc-url=$RPC_URL > /dev/null 2>&1
    BALANCE=$(cast call --rpc-url=$RPC_URL $token "balanceOf(address)(uint256)" $DEPLOYER_PUBLIC_KEY)
    if [ $BALANCE == 0 ]; then
        echo "Error: Failed to transfer $token to $DEPLOYER_PUBLIC_KEY"
        exit 1
    fi
done
