## Information

This part contains various scripts located in the `package.json` script section. Deployment scripts can be found in the
`deployments` folder.

### Deployment Details

- All scripts are located in the package.json script section.
- Deployment scripts are placed in the deployments folder.
- Each deploy script is independent and can be directly called. The instances of manager, ithil, and oracle are provided
  from the data folder.
- Manager and Vaults are unique. Therefore, for each manager you deploy, you can only have one vault for each token.
  When calling the vault for the same manager, it won't redeploy them but will only overwrite the previous vaults.
- Other deployments are not unique and can be called multiple times for the same manager/vaults.
- Static data can be modified within the ./config.ts file.
- Tokens are simplified for the frontend, which explains the inclusion of extra non-essential properties.
- The manager is rewritten multiple times during the deploy:all script, and that is acceptable. This implementation is
  necessary due to the absence of a data file inside the frontend project. Therefore, for each instance, we rewrite the
  data as they can also be directly called.

# Correct order of invocation

- faucet (addresses needs money) / run faucet
- deploy (deploys contracts) run deploy:manager, deploy:vaults, ...
- OPTIONAL: fill-vaults (vaults need tokens) run hardhat:vaults:tenderly
