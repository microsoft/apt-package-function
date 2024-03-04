#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -euo pipefail

# This script uses Bicep scripts to create a function app and a storage account,
# then uses the Azure CLI to deploy the function code to that app.

LOCATION="eastus"

function usage()
{
    echo "Usage: $0 [-l <LOCATION>] [-s <CUSTOM SUFFIX>] <RESOURCE GROUP NAME>"
    echo
    echo "By default, location is '${LOCATION}'"
    echo "A list of location names can be obtained by running 'az account list-locations --query \"[].name\"'"
}

PARAMETERS=""

while getopts ":l:s:" opt; do
    case "${opt}" in
        l)
            LOCATION=${OPTARG}
            ;;
        s)
            PARAMETERS="${PARAMETERS} --parameter suffix=${OPTARG}"
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND-1))

# Takes parameters of the resource group name.
RESOURCE_GROUP_NAME=${1:-}

if [[ -z ${RESOURCE_GROUP_NAME} ]]
then
  echo "Requires a resource group name"
  echo
  usage
  exit 1
fi

echo "Ensuring resource group ${RESOURCE_GROUP_NAME} exists"
az group create --name "${RESOURCE_GROUP_NAME}" --location "${LOCATION}" --output none

# Create the resources
DEPLOYMENT_NAME="${RESOURCE_GROUP_NAME}"
echo "Creating resources in resource group ${RESOURCE_GROUP_NAME}"
az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --template-file ./rg.bicep \
  ${PARAMETERS} \
  --output none
echo "Resources created"

# There's some output in the deployment that we need.
APT_SOURCES=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.apt_sources.value)
FUNCTION_APP_NAME=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.function_app_name.value)
STORAGE_ACCOUNT=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.storage_account.value)
PACKAGE_CONTAINER=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.package_container.value)

# Zip up the functionapp code
mkdir -p build/
rm -f build/function_app.zip
zip -r build/function_app.zip host.json requirements.txt function_app.py

# Deploy the function code
echo "Deploying function app code to ${FUNCTION_APP_NAME}"
az functionapp deployment source config-zip \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --name "${FUNCTION_APP_NAME}" \
    --src build/function_app.zip \
    --build-remote true \
    --output none
echo "Function app code deployed"

# Clean up
rm -f build/function_app.zip

# Now run the second deployment script to create the eventgrid subscription.
# This must be run after the function app is deployed, because the ARM ID of the
# eventGridTrigger function doesn't exist until after deployment.
az deployment group create \
  --name "${DEPLOYMENT_NAME}_eg" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --template-file ./rg_add_eventgrid.bicep \
  ${PARAMETERS} \
  --output none

# Report to the user how to use this repository
echo "The repository has been created!"
echo "You can upload packages to the container '${PACKAGE_CONTAINER}' in the storage account '${STORAGE_ACCOUNT}'."
echo "The function app '${FUNCTION_APP_NAME}' will be triggered by new packages"
echo "in that container and regenerate the repository."
echo
echo "To download packages, you need to have apt-transport-blob installed on your machine."
echo "Next, add this line to /etc/apt/sources.list:"
echo
echo "  ${APT_SOURCES}"
echo
echo "Ensure that you have a valid Azure credential, (either by logging in with 'az login' or "
echo "by setting the AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID environment variables)."
echo "That credential must have 'Storage Blob Data Reader' access to the storage account."
echo "Then you can use apt-get update and apt-get install as usual."
