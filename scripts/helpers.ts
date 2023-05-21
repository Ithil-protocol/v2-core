import { type BigNumber } from '@ethersproject/bignumber'
import { setBalance } from '@nomicfoundation/hardhat-network-helpers'
import { ethers } from 'hardhat'

import { type Address } from './types'

export const fund = async (address: Address, amount: BigNumber = ethers.utils.parseEther('3')) => {
  const balance = await ethers.provider.getBalance(address)
  const thresholdAmount = ethers.utils.parseEther('1')
  if (balance.lt(thresholdAmount)) {
    await setBalance(address, amount)
    console.log(`Funded ${address} with ${ethers.utils.formatEther(amount)}`)
  }
}

export const simpleFund = async (address: Address, amount: BigNumber) => {
  await setBalance(address, amount)
}
