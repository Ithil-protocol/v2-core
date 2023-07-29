import { BigNumber } from '@ethersproject/bignumber'
import { config as dotenvConfig } from 'dotenv'
import { readFileSync, statSync } from 'fs'
import { ethers } from 'hardhat'

import { depositorList } from './address-list'
import { getFrontendDir } from './command-helpers'
import { tokenMap } from './tokens'

// prerequisite: json files containing contracts have to be present
dotenvConfig({ path: '.env.hardhat' })
if (!statSync('.env.hardhat').isFile()) {
  console.warn('No .env.hardhat file found, required to use this script')
  process.exit(1)
}

if (getFrontendDir('') == null) {
  console.warn('No FRONTEND_PATH found in .env.hardhat, required for this script')
  process.exit(1)
}
const contractsPath = getFrontendDir('contracts.json')
const contractsString = readFileSync(contractsPath, 'utf8')
const contracts = JSON.parse(contractsString)

const main = async () => {
  // load liquidity to vaults
  const manager = await ethers.getContractAt('Manager', contracts.manager)

  const [usdcVaultAddress, usdtVaultAddress, wethVaultAddress, btcVaultAddress] = await Promise.all([
    manager.vaults(tokenMap.USDC.tokenAddress),
    manager.vaults(tokenMap.USDT.tokenAddress),
    manager.vaults(tokenMap.WETH.tokenAddress),
    manager.vaults(tokenMap.WBTC.tokenAddress),
  ])
  const [usdcVault, usdtVault, wethVault, btcVault] = await Promise.all([
    ethers.getContractAt('Vault', usdcVaultAddress),
    ethers.getContractAt('Vault', usdtVaultAddress),
    ethers.getContractAt('Vault', wethVaultAddress),
    ethers.getContractAt('Vault', btcVaultAddress),
  ])

  const erc20ApproveAbi = ['function approve(address,uint256)']

  await Promise.all(
    depositorList.map(async (address) => {
      const signer = ethers.provider.getSigner(address)

      const usdc = new ethers.Contract(tokenMap.USDC.tokenAddress, erc20ApproveAbi, signer)
      const usdt = new ethers.Contract(tokenMap.USDT.tokenAddress, erc20ApproveAbi, signer)
      const weth = new ethers.Contract(tokenMap.WETH.tokenAddress, erc20ApproveAbi, signer)
      const wbtc = new ethers.Contract(tokenMap.WBTC.tokenAddress, erc20ApproveAbi, signer)

      // customized vaults with specific signer
      const usdcVaultConnected = usdcVault.connect(signer)
      const usdtVaultConnected = usdtVault.connect(signer)
      const wethVaultConnected = wethVault.connect(signer)
      const btcVaultConnected = btcVault.connect(signer)

      const usdcOneUnit = 10n ** BigInt(tokenMap.USDC.decimals)
      const usdtOneUnit = 10n ** BigInt(tokenMap.USDT.decimals)
      const wethOneUnit = 10n ** BigInt(tokenMap.WETH.decimals)
      const wbtcOneUnit = 10n ** BigInt(tokenMap.WBTC.decimals)

      const usdcAmount = BigNumber.from(1000n * usdcOneUnit)
      const usdtAmount = BigNumber.from(78000n * usdtOneUnit)
      const wethAmount = BigNumber.from(9n * wethOneUnit)
      const wbtcAmount = BigNumber.from(4n * wbtcOneUnit)

      const overrides = {
        gasLimit: 2_000_000,
      }

      await Promise.all([
        usdc.approve(usdcVault.address, usdcAmount, overrides),
        usdt.approve(usdtVault.address, usdtAmount, overrides),
        weth.approve(wethVault.address, 9n * wethOneUnit, overrides),
        wbtc.approve(btcVault.address, 4n * wbtcOneUnit, overrides),
      ])

      await Promise.all([
        usdcVaultConnected.deposit(usdcAmount, address, overrides),
        usdtVaultConnected.deposit(usdtAmount, address, overrides),
        wethVaultConnected.deposit(wethAmount, address, overrides),
        btcVaultConnected.deposit(wbtcAmount, address, overrides),
      ])
    }),
  )

  console.log(`Filled vaults with:
  - USDC: ${91 * depositorList.length}k
  - USDT: ${78 * depositorList.length}k
  - WETH: ${9 * depositorList.length}
  - WBTC: ${4 * depositorList.length}
`)
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
