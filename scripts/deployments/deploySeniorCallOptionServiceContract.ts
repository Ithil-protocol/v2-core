import { readFileSync } from 'fs'
import { ethers } from 'hardhat'

import type { CallOption } from '../../typechain-types'
import { rewriteJsonFile, useHardhatENV } from '../command-helpers'
import { frontendVaultsJsonDir, oneMinute, oneSecond, vaultsJsonDir } from '../config'
import { configCreditService } from '../contracts'
import { tokens } from '../tokens'
import type { AcceptedAssetEnum, LendingToken, MinimalToken } from '../types'
import { deployIthilContract } from './deployIthilContract'
import { deployManagerContract } from './deployManagerContract'

useHardhatENV()
interface DeployCallOptionServiceContractProps {
  isNewDeploy: boolean
  callOptionTokens: MinimalToken[]
}

type AllCallOptions = {
  [key in AcceptedAssetEnum]?: CallOption
}
async function deployCallOptionServiceContract({
  isNewDeploy,
  callOptionTokens,
}: DeployCallOptionServiceContractProps) {
  const allCallOptions: AllCallOptions = {}
  if (isNewDeploy) {
    const manager = await deployManagerContract({ isNewDeploy: false })
    const ithil = await deployIthilContract({ isNewDeploy: false })

    const CallOption = await ethers.getContractFactory('CallOption')

    await Promise.all(
      callOptionTokens.map(async (token) => {
        const callOptionService = await CallOption.deploy(
          manager.address,
          ithil.address,
          BigInt(token.initialPriceForIthil),
          oneMinute,
          oneSecond,
          0n,
          token.tokenAddress,
        )
        await callOptionService.deployed()
        console.log(`callOptionService contract deployed to ${callOptionService.address}`)

        await configCreditService({ manager, service: callOptionService, serviceTokens: [token] })
        await ithil.approve(callOptionService.address, 1000000n * 10n ** 18n)
        await callOptionService.allocateIthil(100000n * 10n ** 18n) // allocate 100_000 ithil

        allCallOptions[token.name] = callOptionService
      }),
    )
    const vaultJson = readFileSync(vaultsJsonDir, 'utf8')
    const vaults = JSON.parse(vaultJson) as LendingToken[]
    const newVaults = vaults.map((token) => ({ ...token, callOptionAddress: allCallOptions[token.name]!.address }))
    rewriteJsonFile(vaultsJsonDir, newVaults)
    rewriteJsonFile(frontendVaultsJsonDir, newVaults)
  } else {
    const vaultJson = readFileSync(vaultsJsonDir, 'utf8')
    const vaults = JSON.parse(vaultJson) as LendingToken[]
    await Promise.all(
      vaults.map(async (token) => {
        const callOptionService = await ethers.getContractAt('CallOption', token.callOptionAddress)
        console.log(`callOptionService contract instance created with this address: ${callOptionService.address}`)
        allCallOptions[token.name] = callOptionService
      }),
    )
  }

  return allCallOptions
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployCallOptionServiceContract({ isNewDeploy: true, callOptionTokens: tokens }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployCallOptionServiceContract }
