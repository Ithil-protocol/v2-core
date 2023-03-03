#/bin/bash
set -e

SCRIPT_DIR=$(pwd)
BROADCAST_DIR=$SCRIPT_DIR/../../broadcast
DEPLOYMANAGER_LOG=$BROADCAST_DIR/DeployManager.script.sol/42161/run-latest.json
CREATEVAULT_LOG=$BROADCAST_DIR/CreateVault.script.sol/42161/run-latest.json

# vars
PRIVATE_KEY="0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"
WALLET0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
LOCALHOST_RPC="http://localhost:8545"

USDC_CONTRACT="0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
USDT_CONTRACT="0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"

USDC_WHALE="0xf89d7b9c864f589bbF53a82105107622B35EaA40"
USDT_WHALE="0xf89d7b9c864f589bbF53a82105107622B35EaA40"

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

# prepare wallet0
cast rpc anvil_impersonateAccount $USDC_WHALE
cast send $USDC_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDC_WHALE
cast send $USDT_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 \
  --rpc-url $LOCALHOST_RPC --from $USDT_WHALE

# report what has been done
echo -e "\n\n\n"
echo "========== REPORT =========="
echo "moved 10000 USDC and USDT to $WALLET0"
echo "manager: $MANAGER_ADDR"
for i in "${!VAULT_ADDRESSES[@]}"; do
  echo "${VAULT_NAMES[$i]} vault: ${VAULT_ADDRESSES[$i]}"
done
