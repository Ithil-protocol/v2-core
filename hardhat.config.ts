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
      url: 'https://rpc.vnet.tenderly.co/devnet/hardhat01/e7dd3839-2abf-401b-badf-f0c15f614180',
    },
  },
}

export default config
