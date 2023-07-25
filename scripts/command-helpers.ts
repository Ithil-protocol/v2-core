import { readFileSync, writeFileSync } from 'fs'
import path, { resolve } from 'path'

export const getFrontendDir = () => {
  const { FRONTEND_PATH } = process.env
  const projectDir = resolve(__dirname, '..')
  let frontendDir: null | string = null
  if (FRONTEND_PATH == null || FRONTEND_PATH.length === 0) {
    console.warn('No FRONTEND_PATH found in .env.hardhat, will not produce JSON files')
  } else {
    frontendDir = resolve(projectDir, FRONTEND_PATH)
  }

  return frontendDir
}

export const promiseDelay = async (ms: number) => await new Promise((resolve) => setTimeout(resolve, ms))

export const getDataDir = (fileName: string) => {
  return path.resolve(process.cwd(), `scripts/data/${fileName}`)
}

type JsonObject = Record<string, any>

export const updateJsonProperty = (fileName: string, propertyToUpdate: string, newValue: string): void => {
  try {
    const filePath = getDataDir(fileName)
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
