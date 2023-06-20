# hardhat scripts

Files ending with `.script.ts` are meant to be indipendent scripts, and will be launched when executing commands like
`yarn hardhat:deploy:tenderly`

Other files are meant as libraries, and contain functions that can be imported in scripts.

# Brief explanation of scripts

- **deploy.script.ts**  
  Meant the be "the script" to deploy in testnet/production, should do all the required actions to have a working Ithil
  protocol
- **faucet.script.ts**  
  Useful in testnet/devnetwork to send tokens to a set of addresses
- **fill-vaults.script.ts**  
  Useful in testnet/devnetwork to fill the vaults with tokens

# Correct order of invocation

- faucet (addresses needs money)
- deploy (deploys contracts)
- fill-vaults (vaults needs tokens)
