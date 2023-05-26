import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-ethernal'
import { type HardhatUserConfig } from 'hardhat/types'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: 'https://arb1.arbitrum.io/rpc',
      },
    },
    tenderly01: {
      url: 'https://rpc.vnet.tenderly.co/devnet/hardhat01/019f7ffe-a0e0-4476-8613-60ed8f95a08f',
    },
  },
}

export default config
