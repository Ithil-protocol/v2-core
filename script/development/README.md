# launch anvil synthetic network

```bash
anvil -f https://arb-mainnet.g.alchemy.com/v2/it4Um4ecMPP87zNShCGV2GhoFJvxulF8 --state devnetwork.state
```

# bootstrap Anvil network

```
bash -c "cd script/development && bash lending-page.sh"
```

Read the report at the end of the script, like:

```
========== REPORT ==========
moved 10000 USDC and USDT to 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
manager: 0x1Eb835EB7BEEEE9E6bbFe08F16a2d2eF668204bd
USDC vault: 0x960F68E226cA615D296683a1E9cf4ebfdAC8893C
USDT vault: 0xa3d30aF21d6b41e996317556E978248016FFCd44
```

# Cast commands

A cheatsheet is available with useful `cast` commands in the appropriate markdown file [cast.md](cast.md)
