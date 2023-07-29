import { ethers } from 'hardhat'

import type { Ithil } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import { GOVERNANCE, contractJsonDir, currentIthilAddress, frontendContractJsonDir } from '../config'
import type { Address } from '../types'

useHardhatENV()

interface DeployIthilContractProps {
  isNewDeploy: boolean
  governance?: Address
}
async function deployIthilContract({ isNewDeploy, governance = GOVERNANCE }: DeployIthilContractProps) {
  let ithil: Ithil

  if (isNewDeploy) {
    const Ithil = await ethers.getContractFactory('Ithil')
    ithil = await Ithil.deploy(governance)
    await ithil.deployed()
    console.log(`Ithil contract deployed to ${ithil.address}`)
  } else {
    ithil = await ethers.getContractAt('Ithil', currentIthilAddress)
    console.log(`Ithil contract instance created with this address: ${ithil.address}`)
  }

  updateJsonProperty(contractJsonDir, 'ithil', ithil.address)
  updateJsonProperty(frontendContractJsonDir, 'ithil', ithil.address)
  return ithil
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployIthilContract({ isNewDeploy: true, governance: GOVERNANCE }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployIthilContract }
