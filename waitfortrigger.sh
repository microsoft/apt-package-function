#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -euo pipefail

FUNCTION_APP_NAME=$1
RESOURCE_GROUP_NAME=$2

echo "Waiting for event trigger to exist for ${FUNCTION_APP_NAME}"

FUNCTIONS=$(az functionapp function list  -n ${FUNCTION_APP_NAME} -g ${RESOURCE_GROUP_NAME} --query "[].name" --output tsv)
echo "App functions (${FUNCTION_APP_NAME}): ${FUNCTIONS}"
while [[ "${FUNCTIONS}" != *"eventGridTrigger"* ]]
do
  sleep 5
  FUNCTIONS=$(az functionapp function list  -n ${FUNCTION_APP_NAME} -g ${RESOURCE_GROUP_NAME} --query "[].name" --output tsv)
  echo "App functions (${FUNCTION_APP_NAME}): ${FUNCTIONS}"
done
