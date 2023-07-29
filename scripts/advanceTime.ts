import { ethers } from 'hardhat'

import { useHardhatENV } from './command-helpers'
import { oneDay } from './config'

useHardhatENV()

interface AdvanceTimeProps {
  timeToAdvance?: number | bigint
}
async function advanceTime({ timeToAdvance = oneDay }: AdvanceTimeProps) {
  const provider = ethers.provider
  const params = [
    ethers.utils.hexValue(timeToAdvance), // hex encoded number of seconds
  ]

  await provider.send('evm_increaseTime', params)
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void advanceTime({ timeToAdvance: oneDay }).catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { advanceTime }
