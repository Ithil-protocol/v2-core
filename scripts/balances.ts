import { ethers } from 'hardhat'

import { faucetList } from './address-list'
import { tokens } from './tokens'

const main = async () => {
  for (const address of faucetList) {
    console.log('Balances of address:', address)
    for (const token of tokens) {
      const contract = await ethers.getContractAt('IERC20', token.tokenAddress)

      const balanceOf = await contract.balanceOf(address)
      console.log(`${token.name}: ${ethers.utils.formatUnits(balanceOf, token.decimals)}`)
    }

    console.log('-'.repeat(20))
    console.log(' ')
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
if (require.main === module) {
  // Script invoked directly
  void main().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
