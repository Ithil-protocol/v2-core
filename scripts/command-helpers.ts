import { config as dotenvConfig } from 'dotenv'
import { readFileSync, statSync, writeFileSync } from 'fs'
import { artifacts, ethers } from 'hardhat'
import path, { resolve } from 'path'

export const getFrontendDir = (fileName: string) => {
  const { FRONTEND_PATH } = process.env
  const projectDir = process.cwd()
  if (FRONTEND_PATH == null || FRONTEND_PATH.length === 0) {
    console.warn('No FRONTEND_PATH found in .env.hardhat, will not produce JSON files')
    return ''
  } else {
    const frontendProjectDir = resolve(projectDir, FRONTEND_PATH)
    return resolve(frontendProjectDir, `src/deploy/${fileName}`)
  }
}

export const promiseDelay = async (ms: number) => await new Promise((resolve) => setTimeout(resolve, ms))

export const getDataDir = (fileName: string) => {
  return path.resolve(process.cwd(), `scripts/data/${fileName}`)
}

type JsonObject = Record<string, any>

export const updateJsonProperty = (filePath: string, propertyToUpdate: string, newValue: string): void => {
  try {
    // Read the JSON file and parse it into a JavaScript object
    const data = readFileSync(filePath, 'utf8')
    const jsonObject: JsonObject = JSON.parse(data)

    // Check if the selected property exists in the JSON object
    if (propertyToUpdate in jsonObject) {
      // Update the selected property with the new value
      jsonObject[propertyToUpdate] = newValue

      // Write the updated JSON object back to the file
      writeFileSync(filePath, JSON.stringify(jsonObject, null, 2))
      console.log(`Property "${propertyToUpdate}" updated with new value: ${newValue}`)
    } else {
      console.error(`Property "${propertyToUpdate}" not found in the JSON file.`)
    }
  } catch (error) {
    console.error('Error updating JSON property:', error)
  }
}

export const getJsonProperty = (filePath: string, propertyToGet: string): any => {
  try {
    // Read the JSON file and parse it into a JavaScript object
    const data = readFileSync(filePath, 'utf8')
    const jsonObject = JSON.parse(data)

    // Check if the selected property exists in the JSON object
    if (propertyToGet in jsonObject) {
      const propertyValue = jsonObject[propertyToGet]
      return propertyValue
    } else {
      console.error(`Property "${propertyToGet}" not found in the JSON file.`)
      return null
    }
  } catch (error) {
    console.error('Error reading JSON file:', error)
    return null
  }
}

export const getContractInstance = async (contractName: string, contractAddress: string) => {
  // Get the contract's ABI (you need to replace `MyContract` with your actual contract name)
  const contractArtifact = await artifacts.readArtifact(contractName)
  const contractABI = contractArtifact.abi

  // Get the contract instance using the ABI and the contract address
  // const contractInstance = new ethers.Contract(contractAddress, contractABI, ethers.provider)

  // Optionally, you can specify a signer to interact with the contract, if needed
  const signer = ethers.provider.getSigner()
  const contractInstance = new ethers.Contract(contractAddress, contractABI, signer)

  return contractInstance
}

export const useHardhatENV = () => {
  dotenvConfig({ path: '.env.hardhat' })

  if (!statSync('.env.hardhat').isFile()) {
    console.warn('No .env.hardhat file found, required to use tenderly')
    console.warn('Please check .env.hardhat.example for an example')
  }
}
