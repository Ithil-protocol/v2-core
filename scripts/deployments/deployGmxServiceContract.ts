import { ethers } from 'hardhat'

import type { GmxService } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import {
  GMX_ROUTER,
  GMX_ROUTER_V2,
  contractJsonDir,
  currentGmxServiceAddress,
  frontendContractJsonDir,
  oneMonth,
} from '../config'
import { configDebitService } from '../contracts'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()

interface DeployGMXServiceContractProps {
  isNewDeploy: boolean
}
async function deployGMXServiceContract({ isNewDeploy }: DeployGMXServiceContractProps) {
  let gmxService: GmxService

  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const GmxService = await ethers.getContractFactory('GmxService')
    gmxService = await GmxService.deploy(manager.address, GMX_ROUTER, GMX_ROUTER_V2, oneMonth)
    await gmxService.deployed()
    console.log(`GmxService contract deployed to ${gmxService.address}`)

    await configDebitService({
      manager,
      service: gmxService,
    })
  } else {
    gmxService = await ethers.getContractAt('GmxService', currentGmxServiceAddress)
    console.log(`GmxService contract instance created with this address: ${gmxService.address}`)
  }
  updateJsonProperty(contractJsonDir, 'gmxService', gmxService.address)
  updateJsonProperty(frontendContractJsonDir, 'gmxService', gmxService.address)
  return gmxService
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployGMXServiceContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployGMXServiceContract }
