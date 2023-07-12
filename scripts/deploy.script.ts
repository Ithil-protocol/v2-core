import { config as dotenvConfig } from 'dotenv'
import { statSync, writeFileSync } from 'fs'
import { ethers } from 'hardhat'
import { resolve } from 'path'

import { getFrontendDir } from './command-helpers'
import { setCapacity, serviceToggleWhitelist, createVault, deployAave, deployGmx, deployManager } from './contracts'
import { tokens } from './tokens'
import { type LendingToken } from './types'

dotenvConfig({ path: '.env.hardhat' })

if (!statSync('.env.hardhat').isFile()) {
  console.warn('No .env.hardhat file found, required to use tenderly')
  console.warn('Please check .env.hardhat.example for an example')
}

const frontendDir = getFrontendDir()

const AAVE_POOL_ON_ARBITRUM = '0x794a61358D6845594F94dc1DB02A252b5b4814aD'
const GMX_ROUTER = "0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1"
const GMX_ROUTER_V2 = "0xB95DB5B167D75e6d04227CfFFA61069348d271F5"

const main = async () => {
  const manager = await deployManager()
  console.log(`Manager contract deployed to ${manager.address}`)
  const aaveService = await deployAave(manager, AAVE_POOL_ON_ARBITRUM)
  console.log(`AaveService contract deployed to ${aaveService.address}`)
  const gmxService = await deployGmx(manager, GMX_ROUTER, GMX_ROUTER_V2)
  console.log(`GmxService contract deployed to ${gmxService.address}`)

  const vaults = await Promise.all(
    tokens.map(async (token): Promise<LendingToken> => {
      const contract = await ethers.getContractAt('IERC20', token.tokenAddress)
      await contract.approve(manager.address, 100)

      const vaultAddress = await createVault(manager, token.tokenAddress)
      return { ...token, vaultAddress }
    }),
  )

  // Config Aave service
  await Promise.all(tokens.map(async (token) => await setCapacity(manager, aaveService.address, token.tokenAddress)))
  console.log(`Set capacity to 10^18 for ${tokens.length} tokens for Aave`)
  await serviceToggleWhitelist(aaveService, false)
  console.log('Disabled whitelist on Aave service')

  // Config GMX service
  await Promise.all(tokens.map(async (token) => await setCapacity(manager, gmxService.address, token.tokenAddress)))
  console.log(`Set capacity to 10^18 for ${tokens.length} tokens for GMX`)
  await serviceToggleWhitelist(gmxService, false)
  console.log('Disabled whitelist on GMX service')
  
  const contracts = {
    networkUrl: process.env.TENDERLY_URL ?? 'http://localhost:8545',
    manager: manager.address,
    aaveService: aaveService.address,
    gmxService: gmxService.address,
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
