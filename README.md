# apt-package-function

Functionality to create a Debian package repository in Azure Blob Storage with
an Azure Function App to keep it up to date. For use with
[apt-transport-blob](https://github.com/microsoft/apt-transport-blob).

# Getting Started

## Basic usage

To create a new Debian package repository with an Azure Function App, run

```bash
./create_resources.sh <resource_group_name>
```

with the name of the desired resource group. The scripting will autogenerate a
package repository name for you - `debianrepo` followed by a unique string to
differentiate it across Azure.

If you wish to control the suffix used, you can pass the `-s` parameter:

```bash
./create_resources.sh -s <suffix> <resource_group_name>
```
which will attempt to create a storage container named `debianrepo<suffix>`.

By default all resources are created in the `eastus` location - this can be
overridden by passing the `-l` parameter:

```bash
./create_resources.sh -l uksouth <resource_group_name>
```

## No shared-key access / Managed Identities

By default, the storage container that is created has shared-key access enabled.
You can instead create a deployment that uses Managed Identities, but this
requires Docker (as the function application and its dependencies must be
compiled and packed appropriately).

To create a new Debian package repository which uses Managed Identities, run

```bash
./create_resources_nosharedkey.sh [-s <suffix>] [-l <location>] <resource_group_name>
```

This creates an additional blob container (`python`) in the storage account to
hold the compiled function application zip file; the function application is
run directly from that zip file.

# Design

The function app works as follows:

- It is triggered whenever a `.deb` file is uploaded to the monitored blob
  storage container
    - It is triggered by an Event Grid trigger.
- It iterates over all `.deb` files and looks for a matching `.package` file.
- If that file does not exist, it is created
    - The `.deb` file is downloaded and the control information is extracted
    - The hash values for the file are calculated (MD5sum, SHA1, SHA256)
    - All of this information is added to the `.package` file
- All `.package` files are iterated over, downloaded, and combined into a
  single `Package` file, which is then uploaded. A `Packages.xz` file is also
  created.

As the function app works on a Consumption plan it may take up to 10 minutes for
the function app to trigger and regenerate the package information. In practice,
the eventGridTrigger is triggered very quickly.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
