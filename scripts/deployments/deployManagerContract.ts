import { ethers } from 'hardhat'

import type { Manager } from '../../typechain-types'
import { deployerAddress } from '../address-list'
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
  const Manager = await ethers.getContractFactory('Manager')
  if (isNewDeploy) {
    manager = await Manager.deploy()
    await manager.deployed()
    console.log(`Manager contract deployed to ${manager.address}`)
  } else {
    manager = Manager.attach(currentManagerAddress)
    manager.connect(await ethers.getSigner(deployerAddress))

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
