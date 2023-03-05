#/bin/bash
set -e

SCRIPT_DIR=$(pwd)
BROADCAST_DIR=$SCRIPT_DIR/../../broadcast
DEPLOYMANAGER_LOG=$BROADCAST_DIR/DeployManager.script.sol/42161/run-latest.json
CREATEVAULT_LOG=$BROADCAST_DIR/CreateVault.script.sol/42161/run-latest.json

# vars
PRIVATE_KEY="0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"
WALLET0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
# used to load vaults with some liquidity
WALLET1="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
LOCALHOST_RPC="http://localhost:8545"

USDC_CONTRACT="0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
USDT_CONTRACT="0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
DAI_CONTRACT="0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"
WETH_CONTRACT="0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
WBTC_CONTRACT="0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f"

USDC_WHALE="0xf89d7b9c864f589bbF53a82105107622B35EaA40"
USDT_WHALE="0xf89d7b9c864f589bbF53a82105107622B35EaA40"
DAI_WHALE="0xD20E007881ea62B5922B06D025c9dc1D41962953"
WBTC_WHALE="0x171cda359aa49E46Dec45F375ad6c256fdFBD420"

VAULT_ADDRESSES=()
VAULT_NAMES=()

# commands
cd ..
# deploy manager
PRIVATE_KEY=$PRIVATE_KEY \
  forge script -f $LOCALHOST_RPC DeployManager.script.sol --broadcast
MANAGER_ADDR=$(cat $DEPLOYMANAGER_LOG | jq -r '.transactions[0].contractAddress')

# usdc vault
PRIVATE_KEY=$PRIVATE_KEY MANAGER=$MANAGER_ADDR TOKEN=$USDC_CONTRACT \
  forge script -f $LOCALHOST_RPC CreateVault.script.sol --broadcast
LAST_VAULT=$(cat $CREATEVAULT_LOG | jq -r '.transactions[0].additionalContracts[0].address')
VAULT_ADDRESSES+=($LAST_VAULT)
VAULT_NAMES+=("USDC")
# usdt vault
PRIVATE_KEY=$PRIVATE_KEY MANAGER=$MANAGER_ADDR TOKEN=$USDT_CONTRACT \
  forge script -f $LOCALHOST_RPC CreateVault.script.sol --broadcast
LAST_VAULT=$(cat $CREATEVAULT_LOG | jq -r '.transactions[0].additionalContracts[0].address')
VAULT_ADDRESSES+=($LAST_VAULT)
VAULT_NAMES+=("USDT")
# dai vault
PRIVATE_KEY=$PRIVATE_KEY MANAGER=$MANAGER_ADDR TOKEN=$DAI_CONTRACT \
  forge script -f $LOCALHOST_RPC CreateVault.script.sol --broadcast
LAST_VAULT=$(cat $CREATEVAULT_LOG | jq -r '.transactions[0].additionalContracts[0].address')
VAULT_ADDRESSES+=($LAST_VAULT)
VAULT_NAMES+=("DAI")
# weth vault
PRIVATE_KEY=$PRIVATE_KEY MANAGER=$MANAGER_ADDR TOKEN=$WETH_CONTRACT \
  forge script -f $LOCALHOST_RPC CreateVault.script.sol --broadcast
LAST_VAULT=$(cat $CREATEVAULT_LOG | jq -r '.transactions[0].additionalContracts[0].address')
VAULT_ADDRESSES+=($LAST_VAULT)
VAULT_NAMES+=("WETH")
# wbtc vault
PRIVATE_KEY=$PRIVATE_KEY MANAGER=$MANAGER_ADDR TOKEN=$WBTC_CONTRACT \
  forge script -f $LOCALHOST_RPC CreateVault.script.sol --broadcast
LAST_VAULT=$(cat $CREATEVAULT_LOG | jq -r '.transactions[0].additionalContracts[0].address')
VAULT_ADDRESSES+=($LAST_VAULT)
VAULT_NAMES+=("WBTC")

# prepare wallet0
cast rpc anvil_impersonateAccount $USDC_WHALE
cast send $USDC_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDC_WHALE

cast rpc anvil_impersonateAccount $USDT_WHALE
cast send $USDT_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDT_WHALE

cast rpc anvil_impersonateAccount $DAI_WHALE
cast send $DAI_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000000000000000 \
  --rpc-url $LOCALHOST_RPC --from $DAI_WHALE

cast send $WETH_CONTRACT "deposit()" --value 10ether \
  --rpc-url $LOCALHOST_RPC --from $WALLET0

cast send $WBTC_WHALE --from $WALLET1 --value 1ether
cast rpc anvil_impersonateAccount $WBTC_WHALE
cast send $WBTC_CONTRACT "transfer(address,uint256)" $WALLET0 1000000000 \
  --rpc-url $LOCALHOST_RPC --from $WBTC_WHALE

# prepare wallet1
cast rpc anvil_impersonateAccount $USDC_WHALE
cast send $USDC_CONTRACT "transfer(address,uint256)" $WALLET1 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDC_WHALE

cast rpc anvil_impersonateAccount $USDT_WHALE
cast send $USDT_CONTRACT "transfer(address,uint256)" $WALLET1 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDT_WHALE

cast rpc anvil_impersonateAccount $DAI_WHALE
cast send $DAI_CONTRACT "transfer(address,uint256)" $WALLET1 10000000000000000000000 \
  --rpc-url $LOCALHOST_RPC --from $DAI_WHALE

cast send $WETH_CONTRACT "deposit()" --value 10ether \
  --rpc-url $LOCALHOST_RPC --from $WALLET1

cast rpc anvil_impersonateAccount $WBTC_WHALE
cast send $WBTC_CONTRACT "transfer(address,uint256)" $WALLET1 1000000000 \
  --rpc-url $LOCALHOST_RPC --from $WBTC_WHALE

# load liquidity to vaults
USDT_VAULT=${VAULT_ADDRESSES[1]}
DAI_VAULT=${VAULT_ADDRESSES[2]}
WETH_VAULT=${VAULT_ADDRESSES[3]}
WBTC_VAULT=${VAULT_ADDRESSES[4]}
cast send $USDT_CONTRACT "approve(address,uint256)" $USDT_VAULT 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $DAI_CONTRACT "approve(address,uint256)" $DAI_VAULT 10000000000000000000000 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $WETH_CONTRACT "approve(address,uint256)" $WETH_VAULT 10000000000000000000 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $WBTC_CONTRACT "approve(address,uint256)" $WBTC_VAULT 331272300 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1

cast send $USDT_VAULT "deposit(uint256,address)" 2000000000 $WALLET0 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $DAI_VAULT "deposit(uint256,address)" 10000000000000000000000 $WALLET0 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $WETH_VAULT "deposit(uint256,address)" 2530000000000000000 $WALLET0 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1
cast send $WBTC_VAULT "deposit(uint256,address)" 331272300 $WALLET0 \
  --rpc-url $LOCALHOST_RPC --from $WALLET1

# report what has been done
echo -e "\n\n\n"
echo "========== REPORT =========="
echo "moved 10000 USDC, USDT, DAI to $WALLET0"
echo "moved 10 WETH, 10 WBTC to $WALLET0"
echo "filled vaults with 10000 USDT, DAI, 2.53 WETH, 3.312723 WBTC"
echo "manager: $MANAGER_ADDR"
for i in "${!VAULT_ADDRESSES[@]}"; do
  echo "${VAULT_NAMES[$i]} vault: ${VAULT_ADDRESSES[$i]}"
done
