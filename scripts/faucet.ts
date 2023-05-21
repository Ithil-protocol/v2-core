import { ethers } from 'hardhat'

import { fund, simpleFund } from './helpers'
import { type Address } from './types'

const ArbitrumGateway = '0x096760F208390250649E3e8763348E783AEF5562'
const ArbitrumDaiGateway = '0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65'
const ArbitrumBTCGateway = '0x09e9222E96E7B4AE2a407B98d48e330053351EEe'

const mintUSDC = async (destinationAddress: Address) => {
  const tokenAddress = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'
  const impersonatedSigner = await ethers.getImpersonatedSigner(ArbitrumGateway)
  const contract = new ethers.Contract(
    tokenAddress,
    [
      'function balanceOf(address account) view returns (uint256)',
      'function bridgeMint(address account, uint256 amount)',
    ],
    impersonatedSigner,
  )

  await contract.bridgeMint(destinationAddress, 100000n * 10n ** 6n) // 100_000 USDC

  const balanceOf = (await contract.balanceOf(destinationAddress)) as bigint
  console.log(`Balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, 6)}`)
}

const mintUSDT = async (destinationAddress: Address) => {
  const tokenAddress = '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9'
  const impersonatedSigner = await ethers.getImpersonatedSigner(ArbitrumGateway)
  const contract = new ethers.Contract(
    tokenAddress,
    [
      'function balanceOf(address account) view returns (uint256)',
      'function bridgeMint(address account, uint256 amount)',
    ],
    impersonatedSigner,
  )

  await contract.bridgeMint(destinationAddress, 100000n * 10n ** 6n) // 100_000 USDT

  const balanceOf = (await contract.balanceOf(destinationAddress)) as bigint
  console.log(`Balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, 6)}`)
}

const mintDAI = async (destinationAddress: Address) => {
  const tokenAddress = '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1'
  const impersonatedSigner = await ethers.getImpersonatedSigner(ArbitrumDaiGateway)
  const contract = new ethers.Contract(
    tokenAddress,
    ['function balanceOf(address account) view returns (uint256)', 'function mint(address account, uint256 amount)'],
    impersonatedSigner,
  )

  await contract.mint(destinationAddress, 100000n * 10n ** 18n) // 100_000 DAI

  const balanceOf = (await contract.balanceOf(destinationAddress)) as bigint
  console.log(`Balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, 18)}`)
}

const mintBTC = async (destinationAddress: Address) => {
  const tokenAddress = '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f'
  const impersonatedSigner = await ethers.getImpersonatedSigner(ArbitrumBTCGateway)
  const contract = new ethers.Contract(
    tokenAddress,
    [
      'function balanceOf(address account) view returns (uint256)',
      'function bridgeMint(address account, uint256 amount)',
    ],
    impersonatedSigner,
  )

  await contract.bridgeMint(destinationAddress, 10n * 10n ** 8n) // 10 WBTC

  const balanceOf = (await contract.balanceOf(destinationAddress)) as bigint
  console.log(`Balance of ${destinationAddress}: ${ethers.utils.formatUnits(balanceOf, 8)}`)
}

const mintETH = async (destinationAddress: Address) => {
  const tokenAddress = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'
  await simpleFund(destinationAddress, ethers.utils.parseEther('200'))
  const impersonatedSigner = await ethers.getImpersonatedSigner(destinationAddress)

  const contract = new ethers.Contract(
    tokenAddress,
    ['function balanceOf(address account) view returns (uint256)', 'function deposit() payable'],
    impersonatedSigner,
  )

  await contract.deposit({ value: ethers.utils.parseEther('100') })
  const balanceWETH = (await contract.balanceOf(destinationAddress)) as bigint
  const balanceETH = await ethers.provider.getBalance(destinationAddress)

  console.log(
    `Balance of ${destinationAddress}: ${ethers.utils.formatEther(balanceWETH)} WETH, ${ethers.utils.formatEther(
      balanceETH,
    )} ETH`,
  )
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
  await fund(ArbitrumGateway)
  await fund(ArbitrumDaiGateway)
  await fund(ArbitrumBTCGateway)

  await Promise.all(
    addressList.map(async (address) => {
      await mintUSDC(address)
      await mintUSDT(address)
      await mintDAI(address)
      await mintBTC(address)
      await mintETH(address)
    }),
  )

  console.log(`Funded ${addressList.length} addresses with 100k USDC-USDT-DAI, 20 WBTC, 100 ETH-WETH`)
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
