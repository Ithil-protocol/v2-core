import { ethers } from 'hardhat'

import type { Manager } from '../../typechain-types'
import { getDataDir, getFrontendDir, getJsonProperty, updateJsonProperty, useHardhatENV } from '../command-helpers'

useHardhatENV()

const contractJsonDir = getDataDir('contracts.json')
const frontendContractJsonDir = getFrontendDir('contracts.json')

const currentManagerAddress = getJsonProperty(contractJsonDir, 'manager')

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
