#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -euo pipefail

# This script uses Bicep scripts to create a function app and a storage account,
# then uses the Azure CLI to deploy the function code to that app.
# Uses managed identities.
# Requires Docker to be installed and running.

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

# Pack the application using the core-tools tooling
# Should generate a file called function_app.zip
docker run -it \
  --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $PWD:/function_app \
  -w /function_app \
  mcr.microsoft.com/azure-functions/python:4-python3.11-core-tools \
  bash -c "func pack --python --build-native-deps"

echo "Ensuring resource group ${RESOURCE_GROUP_NAME} exists"
az group create --name "${RESOURCE_GROUP_NAME}" --location "${LOCATION}" --output none

# Create the resources
DEPLOYMENT_NAME="${RESOURCE_GROUP_NAME}"
echo "Creating resources in resource group ${RESOURCE_GROUP_NAME}"
az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --template-file ./rg.bicep \
  --parameter use_shared_keys=false \
  ${PARAMETERS} \
  --output none
echo "Resources created"

# There's some output in the deployment that we need.
APT_SOURCES=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.apt_sources.value)
STORAGE_ACCOUNT=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.storage_account.value)
PACKAGE_CONTAINER=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.package_container.value)
PYTHON_CONTAINER=$(az deployment group show -n "${DEPLOYMENT_NAME}" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.python_container.value)

# Upload the function app code to the python container
echo "Uploading function app code to ${PYTHON_CONTAINER}"
az storage blob upload \
  --auth-mode login \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${PYTHON_CONTAINER}" \
  --file function_app.zip \
  --name function_app.zip \
  --overwrite \
  --output none

# Create the function app
echo "Creating function app in resource group ${RESOURCE_GROUP_NAME}"
az deployment group create \
  --name "${DEPLOYMENT_NAME}_func" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --template-file ./rg_funcapp.bicep \
  --parameter use_shared_keys=false \
  ${PARAMETERS} \
  --output none
echo "Function App created"

# Get the generated function app name
FUNCTION_APP_NAME=$(az deployment group show -n "${DEPLOYMENT_NAME}_func" -g "${RESOURCE_GROUP_NAME}" --output tsv --query properties.outputs.function_app_name.value)

# Clean up
rm -f function_app.zip

# Wait for the event trigger to exist
./waitfortrigger.sh "${FUNCTION_APP_NAME}" "${RESOURCE_GROUP_NAME}"

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
