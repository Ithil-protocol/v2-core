import { BigNumber } from '@ethersproject/bignumber'
import { setBalance } from '@nomicfoundation/hardhat-network-helpers'
import axios from 'axios'
import { ethers } from 'hardhat'

import { faucetList } from './address-list'
import { useHardhatENV } from './command-helpers'
import type { Address, MinimalToken, Replacement } from './types'

useHardhatENV()

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

export const simpleFundTenderly = async (address: Address, amount: bigint) => {
  await ethers.provider.send('tenderly_addBalance', [[address], ethers.utils.hexValue(amount)])
}

export const findStorageSlot = async (address: Address, toFind: Address, scanAmount = 1000) => {
  const stringToFind = toFind.substring(2).toLowerCase()
  const storageArray = new Array(scanAmount).fill(0).map((_, i) => i)
  const values = await Promise.all(storageArray.map(async (slot) => await ethers.provider.getStorageAt(address, slot)))

  const filteredValues = values
    .map((value, idx) => ({ value, idx }))
    .filter(({ value }) => {
      const num = BigNumber.from(value)
      return num.gt(0)
    })

  filteredValues.forEach(({ value, idx }) => {
    console.log(`Slot ${idx.toString().padStart(3, '0')}: ${value}`)
  })

  const found = filteredValues.find(({ value }) => {
    const dataWithoutPrefix = value.substring(2)
    const findIdx = dataWithoutPrefix.indexOf(stringToFind)
    return findIdx !== -1
  })

  if (found == null) return null

  const dataWithoutPrefix = found.value.substring(2)
  const findIdx = dataWithoutPrefix.indexOf(stringToFind)
  return { slot: found.idx, from: findIdx, to: findIdx + stringToFind.length, value: found.value } as Replacement
}

export const faucetERC20Token = async (
  token: MinimalToken,
  accounts: Address[] = faucetList,
  amount: bigint,
  url: string,
) => {
  for (const account of accounts) {
    const data = {
      jsonrpc: '2.0',
      method: 'tenderly_setErc20Balance',
      params: [token.tokenAddress, account, ethers.utils.hexValue(amount * 10n ** BigInt(token.decimals))],
      id: '1234',
    }
    try {
      await axios.post(url, data)
      console.log(`Funded account ${account} with ${amount} ${token.name}`)
    } catch (error: any) {
      console.error(`ERROR: couldn't fund account ${account} with ${token.name}`, error.message)
    }
  }
}
