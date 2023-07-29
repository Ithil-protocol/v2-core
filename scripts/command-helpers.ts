import { config as dotenvConfig } from 'dotenv'
import fs, { readFileSync, statSync, writeFileSync } from 'fs'
import path, { resolve } from 'path'

import { type JsonObject } from './types'

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
  const filePath = path.resolve(process.cwd(), `scripts/data/${fileName}`)

  // Check if the file exists at the resolved path
  try {
    fs.accessSync(filePath, fs.constants.F_OK)
    // If the file exists, so we can return the path
    return filePath
  } catch (error) {
    throw new Error(`File not found: ${fileName}`)
  }
}

export const updateJsonProperty = (filePath: string, propertyToUpdate: string, newValue: string): void => {
  try {
    // Read the JSON file and parse it into a JavaScript object
    const data = readFileSync(filePath, 'utf8')
    const jsonObject: JsonObject = JSON.parse(data)

    // Check if the selected property exists in the JSON object
    if (propertyToUpdate in jsonObject) {
      console.log(`Property "${propertyToUpdate}" updated with new value: ${newValue}`)
    } else {
      console.log(`add new property "${propertyToUpdate}" with this value: ${newValue}.`)
    }
    jsonObject[propertyToUpdate] = newValue
    // Write the updated JSON object back to the file
    writeFileSync(filePath, JSON.stringify(jsonObject, null, 2))
  } catch (error) {
    console.error('Error updating JSON property:', error)
  }
}

export const rewriteJsonFile = (filePath: string, newData: any): void => {
  try {
    // Convert the provided data to a JSON string
    const jsonString = JSON.stringify(newData, null, 2)

    // Write the JSON string to the file, effectively overwriting the old content
    writeFileSync(filePath, jsonString, 'utf8')

    console.log(`File "${filePath}" has been rewritten with new data:`)
    console.log(jsonString)
  } catch (error) {
    console.error(`Error rewriting JSON file "${filePath}":`, error)
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

// export const getContractInstance = async (contractName: string, contractAddress: string) => {
//   // Get the contract's ABI (you need to replace `MyContract` with your actual contract name)
//   const contractArtifact = await artifacts.readArtifact(contractName)
//   const contractABI = contractArtifact.abi

//   // Get the contract instance using the ABI and the contract address
//   // const contractInstance = new ethers.Contract(contractAddress, contractABI, ethers.provider)

//   // Optionally, you can specify a signer to interact with the contract, if needed
//   const signer = await ethers.getSigner(deployerAddress)
//   const contractInstance = new ethers.Contract(contractAddress, contractABI, signer)

//   return contractInstance
// }

export const useHardhatENV = () => {
  dotenvConfig({ path: '.env.hardhat' })

  if (!statSync('.env.hardhat').isFile()) {
    console.warn('No .env.hardhat file found, required to use tenderly')
    console.warn('Please check .env.hardhat.example for an example')
  }
}
