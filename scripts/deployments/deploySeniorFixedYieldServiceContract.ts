import { ethers } from 'hardhat'

import type { FixedYieldService } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import { contractJsonDir, currentFixedYieldServiceAddress, frontendContractJsonDir, oneDay } from '../config'
import { configCreditService } from '../contracts'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()

interface DeployFixedYieldServiceContractProps {
  isNewDeploy: boolean
}
async function deployFixedYieldServiceContract({ isNewDeploy }: DeployFixedYieldServiceContractProps) {
  let FixedYieldService: FixedYieldService

  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const FixedYieldService = await ethers.getContractFactory('FixedYieldService')
    FixedYieldService = await FixedYieldService.deploy(manager.address, 10n ** 16n, oneDay * 30n)

    await FixedYieldService.deployed()
    console.log(`FixedYieldService contract deployed to ${FixedYieldService.address}`)

    await configCreditService({
      manager,
      service: FixedYieldService,
    })
  } else {
    FixedYieldService = await ethers.getContractAt('FixedYieldService', currentFixedYieldServiceAddress)
    console.log(`FixedYieldService contract instance created with this address: ${FixedYieldService.address}`)
  }
  updateJsonProperty(contractJsonDir, 'fixedYieldService', FixedYieldService.address)
  updateJsonProperty(frontendContractJsonDir, 'fixedYieldService', FixedYieldService.address)
  return FixedYieldService
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployFixedYieldServiceContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployFixedYieldServiceContract }
