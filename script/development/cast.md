# Move Assets into wallet0

USDC

```
USDC_CONTRACT="0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
USDC_WHALE="0x637842536b989BCFFe15c1678Fc558986c503548"
WALLET0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
cast send $USDC_WHALE --from $WALLET0 --value 1ether
cast rpc anvil_impersonateAccount $USDC_WHALE
cast send $USDC_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 --rpc-url localhost:8545 --from $USDC_WHALE
```

USDT

```
USDT_CONTRACT="0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
USDT_WHALE="0xf89d7b9c864f589bbF53a82105107622B35EaA40"
WALLET0="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
cast rpc anvil_impersonateAccount $USDT_WHALE
cast send $USDT_CONTRACT "transfer(address,uint256)" $WALLET0 10000000000 --rpc-url localhost:8545 --from $USDT_WHALE
```

Double check:

```
> cast call $USDC_CONTRACT "balanceOf(address)" $WALLET0 --rpc-url localhost:8545
0x00000000000000000000000000000000000000000000000000000002540be400

> echo $(( 16#2540be400 ))
10000000000
```

## Interact with vault

```
USDC_VAULT="0x960F68E226cA615D296683a1E9cf4ebfdAC8893C"
USDT_VAULT="0xa3d30aF21d6b41e996317556E978248016FFCd44"
cast call $USDC_VAULT "asset()"
cast call $USDT_VAULT "asset()"
```

- missing: check approve to vault OR pre-approval

approve to vault:

```
cast send $USDC_CONTRACT "approve(address,uint256)" $USDC_VAULT 100000000000 --rpc-url localhost:8545 --from $WALLET0
```

deposit:

```
cast send $USDC_VAULT "deposit(uint256,address)" 2000000000 $WALLET0 --rpc-url localhost:8545 --from $WALLET0
```

totalAssets:

```
cast call $USDC_VAULT "totalAssets()"
```

freeLiquidity (specific for Ithil) - unused Liquidity:

```
cast call $USDC_VAULT "freeLiquidity()"
```

signature of withdraw `withdraw(uint256 assets, address receiver, address owner)`

```
cast send $USDC_VAULT "withdraw(uint256,address,address)" 2000000000 $WALLET0 $WALLET0 --rpc-url localhost:8545 --from $WALLET0
```

signature of redeem `redeem(uint256 shares, address receiver, address owner)`

```
cast send $USDC_VAULT "redeem(uint256,address,address)" 1999999999 $WALLET0 $WALLET0 --rpc-url localhost:8545 --from $WALLET0
```

**Check maxWithdraw(address) or maxRedeem(address) before withdraw/redeem!**

how to increment value of a Vault

```
cast send $WETH_CONTRACT "transfer(address,uint256)" $WETH_VAULT 1000000000000000000 --rpc-url localhost:8545 --from $WALLET1
cast call $WETH_VAULT "convertToAssets(uint256)" 1000000000000000000 --rpc-url localhost:8545
```

```
cast call $DAI_VAULT "convertToAssets(uint256)" 100000000000000000000 --rpc-url localhost:8545
> 100
cast send $DAI_CONTRACT "transfer(address,uint256)" $DAI_VAULT 1000000000000000000000 --rpc-url localhost:8545 --from $DAI_WHALE
cast call $DAI_VAULT "convertToAssets(uint256)" 100000000000000000000 --rpc-url localhost:8545
> 110
```

Remove shares from wallet1 from vault

```
cast call $WETH_VAULT "balanceOf(address)" $WALLET1 --rpc-url localhost:8545
> 2.53
cast send $WETH_VAULT "redeem(uint256,address,address)" 2530000000000000000 $WALLET1 $WALLET1 --rpc-url localhost:8545 --from $WALLET1
```
