// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

// This file creates all the resource group scope resources
targetScope = 'resourceGroup'

@description('Unique suffix')
param suffix string = uniqueString(resourceGroup().id)

@description('The location of the resources')
param location string = resourceGroup().location

@description('The name of the function app to use')
param appName string = 'debfnapp${suffix}'

// Storage account names must be between 3 and 24 characters, and unique, so
// generate a unique name.
@description('The name of the storage account to use')
param storage_account_name string = 'debianrepo${suffix}'

// Choose the package container name. This will be passed to the function app.
var package_container_name = 'packages'

// The version of Python to run with
var python_version = '3.11'

// The name of the hosting plan, application insights, and function app
var functionAppName = appName
var hostingPlanName = appName
var applicationInsightsName = appName

// Create a storage account for both package storage and function app storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storage_account_name
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
  }
}

// Create a container for the packages
resource defBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}
resource packageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: defBlobServices
  name: package_container_name
  properties: {
  }
}

// Create a default Packages file if it doesn't exist using a deployment script
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createPackagesFile${suffix}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.28.0'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storageAccount.name
      }
      {
        name: 'AZURE_BLOB_CONTAINER'
        value: packageContainer.name
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storageAccount.listKeys().keys[0].value
      }
    ]
    // This script preserves the Packages file if it exists and creates it
    // if it does not.
    scriptContent: '''
az storage blob download -f Packages -c "${AZURE_BLOB_CONTAINER}" -n Packages || echo "No existing file"
touch Packages
az storage blob upload -f Packages -c "${AZURE_BLOB_CONTAINER}" -n Packages
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Create a hosting plan for the function app
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Create application insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Create the function app.
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      linuxFxVersion: 'Python|${python_version}'
      pythonVersion: python_version
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        // Pass the blob container name to the function app - this is the
        // container which is monitored for new packages.
        {
          name: 'BLOB_CONTAINER'
          value: packageContainer.name
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Create the apt sources string for using apt-transport-blob
output apt_sources string = 'deb [trusted=yes] blob://${storageAccount.name}.blob.core.windows.net/${packageContainer.name} /'
output function_app_name string = functionApp.name
output storage_account string = storageAccount.name
output package_container string = packageContainer.name
