import { BigNumber } from '@ethersproject/bignumber'
import { ethers } from 'hardhat'

import { simpleFundTenderly } from './helpers'
import { tokenMap } from './tokens'
import { type Address, type MinimalToken, type Replacement } from './types'

const replaceContractStorage = async (contractAddress: Address, replacements: Replacement[]) => {
  return await Promise.all(
    replacements.map(async ({ slot, from, to, value }) => {
      const lowerCaseValue = value.substring(2).toLowerCase()
      const origData = await ethers.provider.getStorageAt(contractAddress, slot)
      const origDataWithoutPrefix = origData.substring(2)

      const newData =
        '0x' + origDataWithoutPrefix.substring(0, from) + lowerCaseValue + origDataWithoutPrefix.substring(to)

      return await ethers.provider.send('tenderly_setStorageAt', [
        contractAddress,
        ethers.utils.hexZeroPad(ethers.utils.hexValue(slot), 32),
        newData,
      ])
    }),
  )
}

const genericOverride = async (
  newAddress: Address,
  replacements: Replacement[],
  asset: MinimalToken,
  gatewayFn: string,
) => {
  const signer = ethers.provider.getSigner()
  const contract = new ethers.Contract(asset.tokenAddress, [`function ${gatewayFn}() view returns (address)`], signer)

  const gatewayAddress = await contract[gatewayFn]()
  if (gatewayAddress.toLowerCase() === newAddress.toLowerCase()) return

  await replaceContractStorage(asset.tokenAddress, replacements)
  const gatewayAddressAfter = await contract[gatewayFn]()

  if (gatewayAddressAfter.toLowerCase() !== newAddress.toLowerCase()) throw new Error('Failed to set gateway address')
}

const genericMint = async (destinationAddress: Address, asset: MinimalToken, mintAmount: bigint) => {
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
  await contract.bridgeMint(destinationAddress, mintAmount * oneUnit) // 100_000 USDC

  const balanceOf = (await contract.balanceOf(destinationAddress)) as BigNumber
  console.log(`${asset.name} balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, asset.decimals)}`)
}

const mintWETH = async (signerAddress: Address, destinationAddress: Address, mintAmount: bigint) => {
  const asset = tokenMap.WETH
  const oneUnit = 10n ** BigInt(asset.decimals)
  const signerMintAmount = (mintAmount * 2n + 100n) * oneUnit // 100 extra for gas
  await simpleFundTenderly(signerAddress, signerMintAmount)

  const signer = ethers.provider.getSigner()
  const contract = new ethers.Contract(
    asset.tokenAddress,
    ['function balanceOf(address account) view returns (uint256)', 'function depositTo(address account) payable'],
    signer,
  )

  await contract.depositTo(destinationAddress, { value: BigNumber.from(mintAmount * oneUnit) })
  await signer.sendTransaction({ to: destinationAddress, value: BigNumber.from(mintAmount * oneUnit) })

  const balanceWETH = await contract.balanceOf(destinationAddress)
  const balance = await ethers.provider.getBalance(destinationAddress)
  console.log(`${asset.name} balance of ${destinationAddress}: ${ethers.utils.formatEther(balanceWETH)}`)
  console.log(`ETH balance of ${destinationAddress}: ${ethers.utils.formatEther(balance)}`)
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
  const signer = ethers.provider.getSigner()
  const signerAddress = (await signer.getAddress()) as Address
  const lowerCaseAddress = signerAddress.toLowerCase() as Address

  // USDC override
  await genericOverride(
    lowerCaseAddress,
    [
      {
        slot: 204,
        from: 24,
        to: 64,
        value: lowerCaseAddress,
      },
    ],
    tokenMap.USDC,
    'gatewayAddress',
  )

  await genericOverride(
    lowerCaseAddress,
    [
      {
        slot: 256,
        from: 22,
        to: 62,
        value: lowerCaseAddress,
      },
    ],
    tokenMap.USDT,
    'l2Gateway',
  )

  await genericOverride(
    lowerCaseAddress,
    [
      {
        slot: 204,
        from: 24,
        to: 64,
        value: lowerCaseAddress,
      },
    ],
    tokenMap.WBTC,
    'l2Gateway',
  )

  await Promise.all(
    addressList.map(async (address) => {
      await genericMint(address, tokenMap.USDC, 100000n)
      await genericMint(address, tokenMap.USDT, 100000n)
      await genericMint(address, tokenMap.WBTC, 10n)
      await mintWETH(signerAddress, address, 20n)
    }),
  )
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
