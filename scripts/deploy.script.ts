import { config as dotenvConfig } from 'dotenv'
import { statSync, writeFileSync } from 'fs'
import { ethers } from 'hardhat'
import { resolve } from 'path'

import { getFrontendDir } from './command-helpers'
import { aaveSetCapacity, aaveToggleWhitelist, createVault, deployAave, deployManager } from './contracts'
import { tokens } from './tokens'
import { type LendingToken } from './types'

dotenvConfig({ path: '.env.hardhat' })

if (!statSync('.env.hardhat').isFile()) {
  console.warn('No .env.hardhat file found, required to use tenderly')
  console.warn('Please check .env.hardhat.example for an example')
}

const frontendDir = getFrontendDir()

const AAVE_POOL_ON_ARBITRUM = '0x794a61358D6845594F94dc1DB02A252b5b4814aD'

const main = async () => {
  const manager = await deployManager()
  console.log(`Manager contract deployed to ${manager.address}`)
  const aaveService = await deployAave(manager, AAVE_POOL_ON_ARBITRUM)
  console.log(`AaveService contract deployed to ${aaveService.address}`)

  const vaults = await Promise.all(
    tokens.map(async (token): Promise<LendingToken> => {
      const contract = await ethers.getContractAt('IERC20', token.tokenAddress)
      await contract.approve(manager.address, 100)

      const vaultAddress = await createVault(manager, token.tokenAddress)
      return { ...token, vaultAddress }
    }),
  )

  await Promise.all(tokens.map(async (token) => await aaveSetCapacity(manager, aaveService, token.tokenAddress)))
  console.log(`Set capacity to 10^18 for ${tokens.length} tokens`)
  await aaveToggleWhitelist(aaveService, false)
  console.log('Disabled whitelist on AAVE service')

  const contracts = {
    networkUrl: process.env.TENDERLY_URL ?? 'http://localhost:8545',
    manager: manager.address,
    aaveService: aaveService.address,
  }

  if (frontendDir != null) {
    const contractsPath = resolve(frontendDir, 'src/deploy/contracts.json')
    const vaultsPath = resolve(frontendDir, 'src/deploy/vaults.json')
    writeFileSync(contractsPath, JSON.stringify(contracts, null, 2))
    writeFileSync(vaultsPath, JSON.stringify(vaults, null, 2))

    console.log(`Wrote file vaults.json containing ${vaults.length} vaults`)
    console.log('Wrote file contracts.json containing other deploy addresses')
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
if (require.main === module) {
  // Script invoked directly
  void main().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
