import { readFileSync } from 'fs'
import { ethers } from 'hardhat'

import { rewriteJsonFile, useHardhatENV } from '../command-helpers'
import { frontendVaultsJsonDir, vaultsJsonDir } from '../config'
import { createVault } from '../contracts'
import { tokens } from '../tokens'
import { type LendingToken } from '../types'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()

interface DeployVaultsContractsProps {
  isNewDeploy: boolean
}
async function deployVaultsContracts({ isNewDeploy }: DeployVaultsContractsProps) {
  let vaults: LendingToken[]

  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    vaults = await Promise.all(
      tokens.map(async (token): Promise<LendingToken> => {
        const contract = await ethers.getContractAt('IERC20', token.tokenAddress)
        await contract.approve(manager.address, 100)
        const vaultAddress = await createVault(manager, token.tokenAddress)
        const { initialPriceForIthil, ...restOfTokenProperties } = token
        return { ...restOfTokenProperties, vaultAddress }
      }),
    )
    console.log(`Created ${tokens.length} vaults for this manager: ${manager.address}`)
  } else {
    const data = readFileSync(vaultsJsonDir, 'utf8')
    vaults = JSON.parse(data) as LendingToken[]
  }

  rewriteJsonFile(vaultsJsonDir, vaults)
  rewriteJsonFile(frontendVaultsJsonDir, vaults)
  return vaults
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployVaultsContracts({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployVaultsContracts }
