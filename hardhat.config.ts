import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import * as tdly from '@tenderly/hardhat-tenderly'
import { config as dotenvConfig } from 'dotenv'
import { statSync } from 'fs'
import { type HardhatUserConfig, type NetworkUserConfig } from 'hardhat/types'

import { accountsPrivates } from './scripts/address-list'

dotenvConfig({ path: '.env.hardhat' })

if (!statSync('.env.hardhat').isFile()) {
  console.warn('No .env.hardhat file found, required to use tenderly')
  console.warn('Please check .env.hardhat.example for an example')
}

const { TENDERLY_URL, TENDERLY_CHAINID, TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env
const tenderlyNetwork = {} as NetworkUserConfig & { url?: string }
if (TENDERLY_URL != null && TENDERLY_CHAINID != null && TENDERLY_URL.length > 10) {
  tenderlyNetwork.url = TENDERLY_URL
  tenderlyNetwork.accounts = accountsPrivates
  tenderlyNetwork.chainId = parseFloat(TENDERLY_CHAINID)
}
tdly.setup({ automaticVerifications: true })
const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.18',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        '*': {
          '*': ['abi'],
        },
      },
    },
  },
  defaultNetwork: 'tenderly',

  networks: {
    // hardhat: {
    //   chainId: 1337,
    //   forking: {
    //     url: 'https://arb1.arbitrum.io/rpc',
    //   },
    // },
    tenderly: tenderlyNetwork,
  },
  tenderly: {
    username: TENDERLY_USER!,
    accessKey: TENDERLY_ACCESS_KEY!,
    project: TENDERLY_PROJECT!,
    privateVerification: false,
  },
}

export default config
