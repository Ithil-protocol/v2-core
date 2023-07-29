import { ethers } from 'hardhat'

import type { FeeCollectorService } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import {
  DEFAULT_MANAGER_CAP,
  DEFAULT_MANAGER_CAPACITY,
  GOVERNANCE,
  WETH,
  WIZARDEX,
  contractJsonDir,
  currentFeeCollectorServiceAddress,
  frontendContractJsonDir,
} from '../config'
import { tokens } from '../tokens'
import { deployManagerContract } from './deployManagerContract'
import { deployOracleContract } from './deployOracleContract'

useHardhatENV()

interface DeployFeeCollectorServiceContractProps {
  isNewDeploy: boolean
}
async function deployFeeCollectorServiceContract({ isNewDeploy }: DeployFeeCollectorServiceContractProps) {
  let feeCollectorService: FeeCollectorService

  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const oracle = await deployOracleContract({ isNewDeploy: false })
    const FeeCollectorService = await ethers.getContractFactory('FeeCollectorService')
    feeCollectorService = await FeeCollectorService.deploy(manager.address, WETH, 10n ** 17n, oracle.address, WIZARDEX)
    await feeCollectorService.deployed()
    console.log(`FeeCollectorService contract deployed to ${feeCollectorService.address}`)

    await Promise.all(
      tokens.map(
        async (token) =>
          await manager.setCap(
            feeCollectorService.address,
            token.tokenAddress,
            DEFAULT_MANAGER_CAPACITY,
            DEFAULT_MANAGER_CAP,
          ),
      ),
    )
    await feeCollectorService.transferOwnership(GOVERNANCE)
    console.log(`transferred this service: ${feeCollectorService.address} ownership to ${GOVERNANCE}`)
  } else {
    feeCollectorService = await ethers.getContractAt('FeeCollectorService', currentFeeCollectorServiceAddress)
    console.log(`FeeCollectorService contract instance created with this address: ${feeCollectorService.address}`)
  }
  updateJsonProperty(contractJsonDir, 'feeCollectorService', feeCollectorService.address)
  updateJsonProperty(frontendContractJsonDir, 'feeCollectorService', feeCollectorService.address)
  return feeCollectorService
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployFeeCollectorServiceContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployFeeCollectorServiceContract }
