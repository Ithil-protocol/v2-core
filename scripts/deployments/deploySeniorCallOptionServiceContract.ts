import { readFileSync } from 'fs'
import { ethers } from 'hardhat'

import type { SeniorCallOption } from '../../typechain-types'
import { rewriteJsonFile, useHardhatENV } from '../command-helpers'
import { GOVERNANCE, currentManagerAddress, oneHour, oneMonth, vaultsJsonDir } from '../config'
import { configCreditService } from '../contracts'
import { tokens } from '../tokens'
import type { AcceptedAssetEnum, LendingToken, MinimalToken } from '../types'
import { deployIthilContract } from './deployIthilContract'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()
interface DeploySeniorCallOptionServiceContractProps {
  isNewDeploy: boolean
  callOptionTokens: MinimalToken[]
}

type AllCallOptions = {
  [key in AcceptedAssetEnum]?: SeniorCallOption
}
async function deploySeniorCallOptionServiceContract({
  isNewDeploy,
  callOptionTokens,
}: DeploySeniorCallOptionServiceContractProps) {
  const allCallOptions: AllCallOptions = {}
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

        await configCreditService({ manager, service: callOptionService, serviceTokens: [token] })

        allCallOptions[token.name] = callOptionService
      }),
    )
    const vaultJson = readFileSync(vaultsJsonDir, 'utf8')
    const vaults = JSON.parse(vaultJson) as LendingToken[]
    const newVaults = vaults.map((token) => {
      return { ...token, callOptionAddress: allCallOptions[token.name] }
    })
    rewriteJsonFile(vaultsJsonDir, newVaults)
  } else {
    const vaultJson = readFileSync(vaultsJsonDir, 'utf8')
    const vaults = JSON.parse(vaultJson) as LendingToken[]
    await Promise.all(
      vaults.map(async (token) => {
        const callOptionService = await ethers.getContractAt('SeniorCallOption', token.callOptionAddress)
        console.log(`Manager contract instance created with this address: ${callOptionService.address}`)
        allCallOptions[token.name] = callOptionService
      }),
    )
  }

  // updateJsonProperty(contractJsonDir, 'manager', seniorCallOption.address)
  // updateJsonProperty(frontendContractJsonDir, 'manager', seniorCallOption.address)

  return allCallOptions
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deploySeniorCallOptionServiceContract({ isNewDeploy: false, callOptionTokens: tokens }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deploySeniorCallOptionServiceContract }
