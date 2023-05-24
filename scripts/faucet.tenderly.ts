import { type BigNumber } from '@ethersproject/bignumber'
import { ethers } from 'hardhat'

import { tokenMap } from './tokens'
import { type Address, type Replacement } from './types'

// const ArbitrumGateway = '0x096760F208390250649E3e8763348E783AEF5562'
// const ArbitrumDaiGateway = '0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65'
// const ArbitrumBTCGateway = '0x09e9222E96E7B4AE2a407B98d48e330053351EEe'

const setContractStorage = async (contractAddress: Address, slot: number, value: string) => {
  return await ethers.provider.send('tenderly_setStorageAt', [
    contractAddress,
    ethers.utils.hexZeroPad(ethers.utils.hexValue(slot), 32),
    ethers.utils.hexZeroPad(value, 32),
  ])
}

const replaceContractStorage = async (contractAddress: Address, replacements: Replacement[]) => {
  return await Promise.all(
    replacements.map(async ({ slot, from, to, value }) => {
      const lowerCaseValue = value.substring(2).toLowerCase()
      const origData = await ethers.provider.getStorageAt(contractAddress, slot)
      const origDataWithoutPrefix = origData.substring(2)

      const newData =
        '0x' + origDataWithoutPrefix.substring(0, from) + lowerCaseValue + origDataWithoutPrefix.substring(to)

      console.log({ newData })

      return await ethers.provider.send('tenderly_setStorageAt', [
        contractAddress,
        ethers.utils.hexZeroPad(ethers.utils.hexValue(slot), 32),
        newData,
      ])
    }),
  )
}

const overrideUSDC = async (newAddress: Address, replacements: Replacement[]) => {
  const asset = tokenMap.USDC
  const contract = new ethers.Contract(asset.tokenAddress, ['function gatewayAddress() view returns (address)'])
  const gatewayAddress = await contract.gatewayAddress()

  if (gatewayAddress.toLowerCase() === newAddress.toLowerCase()) return

  await replaceContractStorage(asset.tokenAddress, replacements)
  const gatewayAddressAfter = await contract.gatewayAddress()

  if (gatewayAddressAfter.toLowerCase() !== newAddress.toLowerCase()) throw new Error('Failed to set gateway address')
}

const mintUSDC = async (destinationAddress: Address) => {
  const asset = tokenMap.USDC
  const signer = ethers.provider.getSigner()

  const contract = new ethers.Contract(
    asset.tokenAddress,
    [
      'function balanceOf(address account) view returns (uint256)',
      'function bridgeMint(address account, uint256 amount)',
    ],
    signer,
  )

  const oneUnit = 10n ** BigInt(asset.decimals)
  await contract.bridgeMint(destinationAddress, 100000n * oneUnit) // 100_000 USDC

  const balanceOf = (await contract.balanceOf(destinationAddress)) as BigNumber
  console.log(`${asset.name} balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, asset.decimals)}`)
}

const overrideUSDT = async (newAddress: Address, replacements: Replacement[]) => {
  const asset = tokenMap.USDT
  const contract = new ethers.Contract(asset.tokenAddress, ['function l2Gateway() view returns (address)'])
  const gatewayAddress = await contract.l2Gateway()
  if (gatewayAddress.toLowerCase() === newAddress.toLowerCase()) return

  await replaceContractStorage(asset.tokenAddress, replacements)
  const gatewayAddressAfter = await contract.l2Gateway()

  if (gatewayAddressAfter.toLowerCase() !== newAddress.toLowerCase()) throw new Error('Failed to set gateway address')
}

const mintUSDT = async (destinationAddress: Address) => {
  const asset = tokenMap.USDT
  const signer = ethers.provider.getSigner()

  const contract = new ethers.Contract(
    asset.tokenAddress,
    [
      'function balanceOf(address account) view returns (uint256)',
      'function bridgeMint(address account, uint256 amount)',
    ],
    signer,
  )

  const oneUnit = 10n ** BigInt(asset.decimals)
  await contract.bridgeMint(destinationAddress, 100000n * oneUnit) // 100_000 USDC

  const balanceOf = (await contract.balanceOf(destinationAddress)) as BigNumber
  console.log(`${asset.name} balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, asset.decimals)}`)
}

const addressList: Address[] = [
  // these addresses are from test seed phrase
  '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
  '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC',
  '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
  '0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65',
  '0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc',
  '0x976EA74026E726554dB657fA54763abd0C3a0aa9',
  '0x14dC79964da2C08b23698B3D3cc7Ca32193d9955',
  '0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f',
  '0xa0Ee7A142d267C1f36714E4a8F75612F20a79720',
  '0xBcd4042DE499D14e55001CcbB24a551F3b954096',
]

const main = async () => {
  // const replacement = await findStorageSlot(tokenMap.USDC.tokenAddress, ArbitrumGateway)
  // console.log({ replacement })

  const signer = ethers.provider.getSigner()
  const signerAddress = (await signer.getAddress()) as Address

  // await overrideUSDC(signerAddress, [
  //   {
  //     slot: 204,
  //     from: 24,
  //     to: 64,
  //     value: signerAddress.toLowerCase(),
  //   },
  // ])

  console.log('before usdt')
  await overrideUSDT(signerAddress, [
    {
      slot: 204,
      from: 22,
      to: 62,
      value: signerAddress.toLowerCase(),
    },
  ])
  console.log('after usdt')

  await mintUSDC(addressList[0])
  await mintUSDT(addressList[0])

  // await Promise.all(
  //   addressList.map(async (address) => {
  //     await mintUSDC(address, [
  //       {
  //         slot: 204,
  //         from: 24,
  //         to: 64,
  //         value: signerAddress.toLowerCase(),
  //       },
  //     ])
  //     // await mintUSDT(address)
  //     // await mintDAI(address)
  //     // await mintBTC(address)
  //     // await mintETH(address)
  //   }),
  // )
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
