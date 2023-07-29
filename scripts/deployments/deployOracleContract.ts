import { ethers } from 'hardhat'

import type { Oracle } from '../../typechain-types'
import { updateJsonProperty, useHardhatENV } from '../command-helpers'
import { GOVERNANCE, contractJsonDir, currentOracleAddress, frontendContractJsonDir } from '../config'
import { tokens } from '../tokens'

useHardhatENV()

interface DeployOracleContractProps {
  isNewDeploy: boolean
}
async function deployOracleContract({ isNewDeploy }: DeployOracleContractProps) {
  let oracle: Oracle

  if (isNewDeploy) {
    const PriceConverter = await ethers.getContractFactory('PriceConverter')
    const priceConverter = await PriceConverter.deploy()
    await priceConverter.deployed()

    const Oracle = await ethers.getContractFactory('Oracle', {
      libraries: { PriceConverter: priceConverter.address },
    })
    oracle = await Oracle.deploy()

    await oracle.deployed()
    console.log(`Oracle contract deployed to ${oracle.address}`)

    await Promise.all(tokens.map(async (token) => await oracle.setPriceFeed(token.tokenAddress, token.oracleAddress)))
    console.log(`Set price feed for ${tokens.length} tokens`)

    await oracle.transferOwnership(GOVERNANCE)
    console.log(`transferred the oracle: ${oracle.address} ownership to ${GOVERNANCE}`)
  } else {
    // use contractFactory.attach if a link to PriceConverter needed
    oracle = await ethers.getContractAt('Oracle', currentOracleAddress)
    console.log(`Oracle contract instance created with this address: ${oracle.address}`)
  }

  updateJsonProperty(contractJsonDir, 'oracle', oracle.address)
  updateJsonProperty(frontendContractJsonDir, 'oracle', oracle.address)
  return oracle
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployOracleContract({ isNewDeploy: true }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployOracleContract }
