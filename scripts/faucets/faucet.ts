import axios from 'axios'
import { ethers } from 'hardhat'

import { faucetList } from '../address-list'
import { useHardhatENV } from '../command-helpers'
import { valueNumbers } from '../config'
import { faucetERC20Token } from '../contract-helpers'
import { tokens } from '../tokens'

useHardhatENV()
const url = process.env.TENDERLY_URL!
async function faucet() {
  tokens.forEach(async (token) => await faucetERC20Token(token, faucetList, valueNumbers.THOUSAND * 100n, url))

  try {
    const ethAmount = valueNumbers.THOUSAND * 10n ** 18n
    const requestData = {
      jsonrpc: '2.0',
      method: 'tenderly_addBalance',
      params: [faucetList, ethers.utils.hexValue(ethAmount)],
      id: '1234',
    }

    await axios.post(url, requestData)

    console.log(`Funded ${faucetList.length} accounts with ${ethAmount / 10n ** 18n} ETH`)
  } catch (error: any) {
    console.error(`ERROR: couldn't fund accounts with ETH`, error.message)
  }
}
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void faucet().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
