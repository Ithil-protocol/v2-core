import { faucetList } from '../address-list'
import { useHardhatENV } from '../command-helpers'
import { valueNumbers } from '../config'
import { faucetERC20Token } from '../contract-helpers'
import { tokens } from '../tokens'

useHardhatENV()

async function faucet() {
  tokens.forEach(async (token) => await faucetERC20Token(token, faucetList, valueNumbers.MILLION * 10n))
}
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void faucet().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
