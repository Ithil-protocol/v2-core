import { findStorageSlot } from './contract-helpers'
import { tokenMap } from './tokens'

const ArbitrumGateway = '0x096760F208390250649E3e8763348E783AEF5562'
const ArbitrumDaiGateway = '0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65'
const ArbitrumBTCGateway = '0x09e9222E96E7B4AE2a407B98d48e330053351EEe'

const main = async () => {
  const usdcReplacement = await findStorageSlot(tokenMap.USDC.tokenAddress, ArbitrumGateway, 500)
  console.log({ usdcReplacement })

  const usdtReplacement = await findStorageSlot(tokenMap.USDT.tokenAddress, ArbitrumGateway, 500)
  console.log({ usdtReplacement })

  const daiReplacement = await findStorageSlot(tokenMap.DAI.tokenAddress, ArbitrumDaiGateway, 800)
  console.log({ daiReplacement })

  const wbtcReplacement = await findStorageSlot(tokenMap.WBTC.tokenAddress, ArbitrumBTCGateway, 500)
  console.log({ wbtcReplacement })
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
