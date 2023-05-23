import { BigNumber } from '@ethersproject/bignumber'
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

export const fundTenderly = async (address: Address, amount: BigNumber = ethers.utils.parseEther('3')) => {
  const balance = await ethers.provider.getBalance(address)
  const thresholdAmount = ethers.utils.parseEther('1')
  if (balance.lt(thresholdAmount)) {
    await ethers.provider.send('tenderly_setBalance', [[address], ethers.utils.hexValue(amount.toHexString())])
    console.log(`Funded ${address} with ${ethers.utils.formatEther(amount)}`)
  }
}

export const simpleFundTenderly = async (address: Address, amount: BigNumber) => {
  await ethers.provider.send('tenderly_setBalance', [[address], ethers.utils.hexValue(amount.toHexString())])
}

export const findStorageSlot = async (address: Address, toFind: Address, scanAmount = 1000) => {
  const storageArray = new Array(scanAmount).fill(0).map((_, i) => i)
  const values = await Promise.all(storageArray.map(async (slot) => await ethers.provider.getStorageAt(address, slot)))

  const filteredValues = values.filter((value) => {
    const num = BigNumber.from(value)
    return num.gt(0)
  })
  console.log({ filteredValues })

  const found = values.findIndex((value) => ethers.utils.hexDataSlice(value, 12).toLowerCase() === toFind.toLowerCase())

  if (found !== -1) {
    console.log({ found })
  }
}
