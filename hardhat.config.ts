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
      url: 'https://rpc.vnet.tenderly.co/devnet/hardhat01/f8072df8-0fc3-4426-8df6-6828890612ca',
    },
  },
}

export default config
