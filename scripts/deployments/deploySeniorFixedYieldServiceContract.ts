import { ethers } from 'hardhat'

import type { SeniorFixedYieldService } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import { contractJsonDir, currentFixedYieldServiceAddress, frontendContractJsonDir, oneDay } from '../config'
import { configCreditService } from '../contracts'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()

interface DeploySeniorFixedYieldServiceContractProps {
  isNewDeploy: boolean
}
async function deploySeniorFixedYieldServiceContract({ isNewDeploy }: DeploySeniorFixedYieldServiceContractProps) {
  let seniorFixedYieldService: SeniorFixedYieldService

  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const SeniorFixedYieldService = await ethers.getContractFactory('SeniorFixedYieldService')
    seniorFixedYieldService = await SeniorFixedYieldService.deploy(
      'Fixed yield 1m 1%',
      'FIXED-YIELD-1M1P',
      manager.address,
      10n ** 16n,
      oneDay * 30n,
    )

    await seniorFixedYieldService.deployed()
    console.log(`SeniorFixedYieldService contract deployed to ${seniorFixedYieldService.address}`)

    await configCreditService({
      manager,
      service: seniorFixedYieldService,
    })
  } else {
    seniorFixedYieldService = await ethers.getContractAt('SeniorFixedYieldService', currentFixedYieldServiceAddress)
    console.log(`AaveService contract instance created with this address: ${seniorFixedYieldService.address}`)
  }
  updateJsonProperty(contractJsonDir, 'fixedYieldService', seniorFixedYieldService.address)
  updateJsonProperty(frontendContractJsonDir, 'fixedYieldService', seniorFixedYieldService.address)
  return seniorFixedYieldService
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deploySeniorFixedYieldServiceContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deploySeniorFixedYieldServiceContract }
