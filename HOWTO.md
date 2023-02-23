# launch anvil synthetic network

```bash
anvil -f https://arb-mainnet.g.alchemy.com/v2/it4Um4ecMPP87zNShCGV2GhoFJvxulF8
```

# deploy on Anvil network

```bash
PRIVATE_KEY=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba \
TOKEN0=0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8 \
TOKEN1=0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9 \
forge script \
-f http://localhost:8545 \
script/DeployManager.script.sol --broadcast
```

# Credit many USDC

```
USDC_CONTRACT="0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
USDC_WHALE="0x637842536b989BCFFe15c1678Fc558986c503548"
WALLET0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
cast send $USDC_WHALE --from $WALLET0 --value 1ether
cast rpc anvil_impersonateAccount $USDC_WHALE
cast send $USDC_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 --rpc-url localhost:8545 --from $USDC_WHALE
```

