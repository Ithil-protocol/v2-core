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
import { tokens } from '../tokens'
import { AcceptedAssetEnum, MinimalToken } from '../types'
import { deployIthilContract } from './deployIthilContract'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()
export type AcceptedAsset = 'USDC' | 'USDT' | 'DAI' | 'WETH' | 'WBTC'
interface DeploySeniorCallOptionServiceContractProps {
  isNewDeploy: boolean
  callOptionTokens: MinimalToken[]
}

type AllCallOptions = {
  [key in AcceptedAssetEnum]: SeniorCallOption
}
async function deploySeniorCallOptionServiceContract({
  isNewDeploy,
  callOptionTokens,
}: DeploySeniorCallOptionServiceContractProps) {
  let allCallOptions: AllCallOptions
  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const ithil = await deployIthilContract({ isNewDeploy: false, governance: GOVERNANCE })

    const SeniorCallOption = await ethers.getContractFactory('SeniorCallOption')

    await Promise.all(
      callOptionTokens.map(async (token) => {
        const callOptionService = await SeniorCallOption.deploy(
          manager.address,
          GOVERNANCE,
          ithil.address,
          token.initialPriceForIthil ?? 0n,
          oneMonth,
          oneHour,
          3n * oneHour,
          token.tokenAddress,
        )
        await callOptionService.deployed()
        console.log(`callOptionService contract deployed to ${callOptionService.address}`)
        allCallOptions[token.name] = callOptionService
      }),
    )

    await seniorCallOption.deployed()
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
