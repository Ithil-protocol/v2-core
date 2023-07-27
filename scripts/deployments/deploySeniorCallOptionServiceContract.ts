import { ethers } from 'hardhat'

import type { Manager, SeniorCallOption } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import {
  GOVERNANCE,
  contractJsonDir,
  currentManagerAddress,
  frontendContractJsonDir,
  oneHour,
  oneMonth,
} from '../config'
import { deployIthilContract } from './deployIthilContract'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()

interface DeploySeniorCallOptionServiceContractProps {
  isNewDeploy: boolean
}
async function deploySeniorCallOptionServiceContract({ isNewDeploy }: DeploySeniorCallOptionServiceContractProps) {
  let seniorCallOption: SeniorCallOption
  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const ithil = await deployIthilContract({ isNewDeploy: false, governance: GOVERNANCE })

    const SeniorCallOption = await ethers.getContractFactory('SeniorCallOption')

    seniorCallOption await Promise.all(
    seniorCallOption = await SeniorCallOption.deploy(
      manager.address,
      GOVERNANCE,
      ithil.address,
      initialPrice,
      oneMonth,
      oneHour,
      3n * oneHour,
      underlying,
    )

    await seniorCallOption.deployed()
    console.log(`Manager contract deployed to ${manager.address}`)
    await manager.transferOwnership(GOVERNANCE)
    console.log(`transferred manager ownership to ${GOVERNANCE}`)
  } else {
    seniorCallOption = await ethers.getContractAt('SeniorCallOption', currentManagerAddress)
    console.log(`Manager contract instance created with this address: ${seniorCallOption.address}`)
  }

  updateJsonProperty(contractJsonDir, 'manager', seniorCallOption.address)
  updateJsonProperty(frontendContractJsonDir, 'manager', seniorCallOption.address)
  return seniorCallOption
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deploySeniorCallOptionServiceContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deploySeniorCallOptionServiceContract }
