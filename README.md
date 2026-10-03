# Azure Databricks Private Workspace Deployment

This repository provisions an Azure Databricks workspace with:

- existing resource group
- new VNet created for a given name and CIDR
- new Databricks public/host subnet created from a given CIDR
- new Databricks private/container subnet created from a given CIDR
- new private endpoint subnet created from a given CIDR
- Secure Cluster Connectivity (No Public IP for clusters)
- Optional workspace public network access (controlled by config)
- NoAzureDatabricksRules
- Unity Catalog metastore (provisioned by a dedicated stack)
- 3 private endpoints
- Unity Catalog metastore assignment (after metastore provisioning)
- workspace admin assignment for an account-level group
- optional workspace bootstrap (cluster policies, clusters, SQL warehouses)

## Deployment pattern

- Terraform modules contain provisioning logic
- Terragrunt orchestrates deployments
- config.yaml stores environment-specific inputs

## What this creates

- **Workspace layer (`workspace` stack)**
  - Azure Databricks workspace
  - Private DNS zone or reuse of existing one
  - Private DNS VNet link
  - 3 private endpoints (UI, auth, backend)
  - Databricks Unity Catalog metastore assignment
  - Databricks workspace admin assignment for an account-level group

- **Metastore layer (`metastore` stack)**
  - Databricks Unity Catalog metastore (account-level)
  - Optional default metastore data access using an Azure Databricks Access Connector (when configured)

- **Workspace bootstrap layer (`workspace-bootstrap` stack)**
  - Databricks cluster policies (from `cluster-policy-config.yaml`)
  - Databricks clusters (from `cluster-config.yaml`)
  - Databricks SQL warehouses (from `sql-warehouse-config.yaml`)

## What this does not create

- Resource groups
- Terraform state storage account
- NAT Gateway
- UC schemas

## Prerequisites

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full setup and deployment steps. In short, the following must
already exist:

- Azure resource groups for each environment and for the Terraform state
- ADLS Gen2 storage account with `tfstate` and metastore root containers
- Service principal with Azure roles, a client secret and GitHub federated credentials
- Databricks account with the service principal as account admin
- Databricks account group: DBX_Architect_Lab_Admin
- (Optional) Databricks Access Connector resource (if enabling default metastore data access)

## Authentication

### AzureRM
Use Azure CLI, service principal, or managed identity.

### Databricks account-level provider
Use account-level authentication against:

https://accounts.azuredatabricks.net

The execution identity must be able to:
- create the Unity Catalog metastore
- read account groups
- assign a workspace to a metastore
- assign workspace admin permissions

### Databricks workspace-level provider (workspace bootstrap)

For the `workspace-bootstrap` stack, the Databricks provider is configured with:

- `host` = workspace URL (from the `workspace` stack output)
- `azure_workspace_resource_id` = Azure resource ID of the workspace

Supported authentication flows:

- **Local development (recommended)**: Azure CLI
  - Run `az login` with a user that has access to the workspace subscription/tenant.
  - Optionally run `az account set --subscription "<subscription-id>"`.
  - Then run `terragrunt` in `live/dev/workspace-bootstrap`.

- **CI/CD (GitHub Actions)**: Service principal
  - Use the same service principal variables already defined for Terraform:
    - `ARM_CLIENT_ID`
    - `ARM_CLIENT_SECRET`
    - `ARM_TENANT_ID`
    - `ARM_SUBSCRIPTION_ID`
  - These are already wired in `.github/workflows/terragrunt-deploy.yml`.

## Run

The environment is split into Terragrunt stacks:

- `live/metastore` (Unity Catalog metastore provisioning)
- `live/dev/workspace` (workspace + networking + UC metastore assignment)
- `live/dev/workspace-bootstrap` (policies, clusters, SQL warehouses)

### Required environment variables

The Azure subscription ID and Databricks account ID are not stored in the repo. Terragrunt reads them from
environment variables and fails if they are missing:

| Variable | Used for |
| --- | --- |
| `ARM_SUBSCRIPTION_ID` | Target subscription for resources and the Terraform state backend |
| `DATABRICKS_ACCOUNT_ID` | Databricks account-level provider |
| `DATABRICKS_METASTORE_ID` | Unity Catalog metastore assigned to the workspace (`*/workspace` stacks and their dependents) |
| `DEPLOY_SP_APPLICATION_ID` | Application ID of the deployment service principal, granted on the catalog and external location (`*/workspace-bootstrap` stacks). In GitHub Actions it comes from `AZURE_CLIENT_ID`. |

For local runs, export them before calling `terragrunt`:

```bash
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export DATABRICKS_ACCOUNT_ID="<databricks-account-id>"
export DATABRICKS_METASTORE_ID="<metastore-id>"
export DEPLOY_SP_APPLICATION_ID="<service-principal-application-id>"
```

In GitHub Actions they come from the `AZURE_SUBSCRIPTION_ID`, `DATABRICKS_ACCOUNT_ID` and
`DATABRICKS_METASTORE_ID` secrets of the `dev`, `uat` or `prod` GitHub environment (`prod-*` stacks use
`prod`, `uat-*` stacks use `uat`; all others use `dev`).

### Local run – workspace layer

From `live/dev/workspace`:

```bash
terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

### Local run – metastore layer

From `live/metastore`:

```bash
terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

After applying the metastore stack, set the `DATABRICKS_METASTORE_ID` environment variable (or GitHub environment secret) to the metastore ID it outputs; the workspace stacks read it from there.

### Local run – workspace bootstrap layer

Prerequisite: the workspace stack has been applied successfully.

From `live/dev/workspace-bootstrap`:

```bash
az login
az account set --subscription "<subscription-id>"

terragrunt init
terragrunt validate
terragrunt plan
terragrunt apply
```

### GitHub Actions

`.github/workflows/terragrunt-deploy.yml` is run manually (workflow dispatch). Pick a stack (`metastore`,
`dev-*`, `uat-*` or `prod-*`) and an action (`validate`, `plan`, `apply` or `destroy`).

The job temporarily allow-lists the runner's egress IP on the Terraform state storage account firewall
before running Terragrunt, and removes it again when the job finishes (even on failure). The state storage
account and resource group are set as `TF_STATE_*` variables at the top of the workflow and must match
`remote_state` in `live/root.hcl`.
