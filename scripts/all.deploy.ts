import { config as dotenvConfig } from 'dotenv'
import { statSync, writeFileSync } from 'fs'
import { resolve } from 'path'

import { aaveSetCapacity, aaveToggleWhitelist, createVault, deployAave, deployManager } from './contracts'
import { tokens } from './tokens'
import { type LendingToken } from './types'

dotenvConfig({ path: '.env.hardhat' })

if (!statSync('.env.hardhat').isFile()) {
  console.warn('No .env.hardhat file found, required to use tenderly')
  console.warn('Please check .env.hardhat.example for an example')
}

const { FRONTEND_PATH } = process.env
const projectDir = resolve(__dirname, '..')
let frontendDir: null | string = null
if (FRONTEND_PATH == null || FRONTEND_PATH.length === 0) {
  console.warn('No FRONTEND_PATH found in .env.hardhat, will not produce JSON files')
} else {
  frontendDir = resolve(projectDir, FRONTEND_PATH)
}

const AAVE_POOL_ON_ARBITRUM = '0x794a61358D6845594F94dc1DB02A252b5b4814aD'

const main = async () => {
  const manager = await deployManager()
  console.log(`Manager contract deployed to ${manager.address}`)
  const aaveService = await deployAave(manager, AAVE_POOL_ON_ARBITRUM)
  console.log(`AaveService contract deployed to ${aaveService.address}`)

  const vaults = await Promise.all(
    tokens.map(async (token): Promise<LendingToken> => {
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
