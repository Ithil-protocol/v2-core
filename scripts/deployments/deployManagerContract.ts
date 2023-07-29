import { ethers } from 'hardhat'

import type { Manager } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import { GOVERNANCE, contractJsonDir, currentManagerAddress, frontendContractJsonDir } from '../config'

useHardhatENV()

interface DeployManagerContractProps {
  isNewDeploy: boolean
}
async function deployManagerContract({ isNewDeploy }: DeployManagerContractProps) {
  let manager: Manager
  if (isNewDeploy) {
    const Manager = await ethers.getContractFactory('Manager')
    manager = await Manager.deploy()
    await manager.deployed()
    console.log(`Manager contract deployed to ${manager.address}`)

    const managerBlockNumber = manager.deployTransaction.blockNumber!.toString()
    updateJsonProperty(contractJsonDir, 'managerBlockNumber', managerBlockNumber)
    updateJsonProperty(frontendContractJsonDir, 'managerBlockNumber', managerBlockNumber)

    await manager.transferOwnership(GOVERNANCE)
    console.log(`transferred manager ownership to ${GOVERNANCE}`)
  } else {
    manager = await ethers.getContractAt('Manager', currentManagerAddress)
    console.log(`Manager contract instance created with this address: ${manager.address}`)
  }

  updateJsonProperty(contractJsonDir, 'manager', manager.address)
  updateJsonProperty(frontendContractJsonDir, 'manager', manager.address)
  return manager
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployManagerContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployManagerContract }
