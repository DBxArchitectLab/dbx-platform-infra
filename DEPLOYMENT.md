# Deployment guide

How to deploy this repository into a brand-new Azure subscription and Databricks account using the
GitHub Actions workflow (`.github/workflows/terragrunt-deploy.yml`).

Deployment order:

```
1. Repo config  →  2. Azure prerequisites  →  3. Databricks account  →  4. GitHub setup
                                                                             │
   5. Deploy:  metastore  →  dev-workspace  →  dev-workspace-bootstrap  →  (uat, prod)
```

Values used throughout this guide (change them if yours differ):

| Name | Value | Defined in |
| --- | --- | --- |
| Region | `centralus` | `live/*/config.yaml`, `live/metastore/config.yaml` |
| Shared resource group (state + metastore storage) | `rg-dbx-architect-lab` | `live/root.hcl`, workflow `TF_STATE_RESOURCE_GROUP` |
| Shared storage account | `adlsdbxarchitectlab` | `live/root.hcl`, workflow `TF_STATE_STORAGE_ACCOUNT`, `live/metastore/config.yaml` |
| State container | `tfstate` | `live/root.hcl` |
| Metastore root container | `dbx` | `live/metastore/config.yaml` |
| Environment resource groups | `rg-dbx-architect-lab-{dev,uat,prod}` | `live/<env>/config.yaml` |
| GitHub repo | `DBxArchitectLab/dbx-platform-infra-azure` | used for federated credentials |

---

## 1. Finish the repo configuration

Edit and commit these before the first run.

- [ ] **Unique names per environment in `live/<env>/workspace-bootstrap/`.** dev and uat currently use
      identical values, and these must differ:
  - `adls-storage-config.yaml` → `storage_account.name` (globally unique across Azure, 3–24 lowercase
    letters/digits)
  - `catalog-config.yaml` → `catalog.name` (unique within the metastore, which dev/uat/prod share)
  - `external-location-config.yaml` → `external_location.name` (unique within the metastore)
  - `access-connector-config.yaml` → `access_connector.name` (recommended, for clarity)
- [ ] **Metastore owner:** `metastore.owner` in `live/metastore/config.yaml` must be a principal that exists in
      the new Databricks account. Recommended: the group name `DBX_Architect_Lab_Admin` (see step 3).
- [ ] **(Optional) VNet ranges:** dev, uat and prod all use `10.0.0.0/24`. That's fine while the VNets stay
      isolated. Give each environment its own range if they'll ever be peered or connected to a hub network.

## 2. Azure prerequisites

Run these as a user with **Owner** on the subscription.

```bash
SUB="<subscription-id>"
REGION="centralus"
az login
az account set --subscription "$SUB"
```

### 2.1 Register resource providers

`live/root.hcl` sets `resource_provider_registrations = "none"`, so Terraform will not register them for
you. A new subscription needs:

```bash
for ns in Microsoft.Databricks Microsoft.Network Microsoft.Storage Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns" --wait
done
```

### 2.2 Resource groups

The workspace stack reads its resource group; it does not create it.

```bash
az group create -n rg-dbx-architect-lab     -l "$REGION"   # state + metastore storage
az group create -n rg-dbx-architect-lab-dev -l "$REGION"
az group create -n rg-dbx-architect-lab-uat -l "$REGION"
# az group create -n rg-dbx-architect-lab-prod -l "$REGION"   # when you deploy prod
```

### 2.3 State and metastore storage account

Hierarchical namespace (ADLS Gen2) is required for the metastore's `abfss://` root, and can only be set
at creation time.

```bash
az storage account create \
  -n adlsdbxarchitectlab -g rg-dbx-architect-lab -l "$REGION" \
  --sku Standard_LRS --kind StorageV2 --hns true \
  --min-tls-version TLS1_2 --allow-blob-public-access false

SA_ID=$(az storage account show -n adlsdbxarchitectlab -g rg-dbx-architect-lab --query id -o tsv)

# Give yourself data access so you can create the containers with Entra ID auth.
az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Storage Blob Data Contributor" --scope "$SA_ID"

az storage container create --account-name adlsdbxarchitectlab -n tfstate --auth-mode login
az storage container create --account-name adlsdbxarchitectlab -n dbx     --auth-mode login
```

> Role assignments can take a few minutes to apply. If `container create` returns 403, wait and retry.

### 2.4 Service principal for GitHub Actions

```bash
SP_NAME="sp-dbx-platform-infra"
az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "/subscriptions/$SUB"
# Save appId (SP_CLIENT_ID), password (SP_CLIENT_SECRET) and tenant (AZURE_TENANT_ID).

APP_ID="<appId from the output>"

# workspace-bootstrap creates a role assignment on its ADLS account.
for rg in rg-dbx-architect-lab-dev rg-dbx-architect-lab-uat; do
  az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
    --scope "/subscriptions/$SUB/resourceGroups/$rg"
done

# Read/write Terraform state with Entra ID auth (use_azuread_auth = true).
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID"
```

`Contributor` on the subscription also covers the workflow's firewall steps (adding and removing the
runner IP on `adlsdbxarchitectlab`).

**Federated credentials.** The workflow's `azure/login` step signs in with GitHub OIDC (no secret), while
Terraform uses the client secret, so the service principal needs both. Add one federated credential per
GitHub environment:

```bash
for env in dev uat prod; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"github-$env\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:DBxArchitectLab/dbx-platform-infra-azure:environment:$env\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done
```

## 3. Databricks account

1. **Activate the account and find its ID.** A Global Administrator of the Entra ID tenant signs in at
   <https://accounts.azuredatabricks.net> and copies the account ID from the user menu (top right).
   If the console says no account exists, create the account by creating any Azure Databricks workspace
   (Premium tier) in the portal first.
2. **Add the service principal as account admin.** In the account console, go to **User management →
   Service principals → Add**, enter the application ID (`APP_ID`), then open it and turn on the
   **Account admin** role.
3. **Create the group `DBX_Architect_Lab_Admin`** (**User management → Groups**) and add the service principal
   and your user to it. The workspace stack makes this group a workspace admin.
4. **Check for an automatic metastore.** Go to **Catalog** in the account console. If a metastore already
   exists in `centralus` (Databricks creates one automatically with the first workspace in a region), the
   `metastore` stack will fail, because an account can have only one metastore per region. Either:
   - **Use it:** skip the `metastore` stack, copy that metastore's ID for step 4, and make
     `DBX_Architect_Lab_Admin` its admin; or
   - **Replace it:** delete it in the account console (only if nothing uses it), then deploy the
     `metastore` stack as below.

The service principal creates the catalog, storage credential and external location in
`workspace-bootstrap`, so it must be a metastore admin. Setting `metastore.owner` to
`DBX_Architect_Lab_Admin`, with the service principal in that group, covers this.

## 4. GitHub setup

1. **Merge to `main`.** A workflow that you start manually only appears in the **Actions** tab once it
   exists on the default branch.
2. **Create environments** under **Settings → Environments**: `dev`, `uat`, `prod`. Consider adding
   required reviewers on `prod`.
3. **Add these secrets to each environment:**

   | Secret | Value |
   | --- | --- |
   | `SP_CLIENT_ID` | service principal `appId` |
   | `SP_CLIENT_SECRET` | service principal `password` |
   | `AZURE_TENANT_ID` | tenant ID |
   | `AZURE_SUBSCRIPTION_ID` | subscription ID |
   | `DATABRICKS_ACCOUNT_ID` | account ID from step 3 |
   | `DATABRICKS_METASTORE_ID` | metastore ID (set after step 5.1 or 3.4; any placeholder until then) |

   The `metastore` stack runs in the `dev` environment.

## 5. Deploy

Go to **Actions → Terragrunt Deploy Stacks → Run workflow**, choose a **stack** and an **action**. For
each stack, run `plan` first, review the log, then run `apply`.

### 5.1 Metastore (once per region)

| Stack | Action |
| --- | --- |
| `metastore` | `plan`, then `apply` |

Then copy the metastore ID from the account console (**Catalog → your metastore**) or from the
`metastore_id` output at the end of the apply log. Set it as `DATABRICKS_METASTORE_ID` in the `dev`,
`uat` and `prod` environments. They share the metastore because they're in the same region.

### 5.2 dev

| Order | Stack | Creates |
| --- | --- | --- |
| 1 | `dev-dbxarchitectlab-workspace` | VNet, subnets, NSG, private DNS, private endpoints, workspace, metastore assignment, admin group assignment |
| 2 | `dev-dbxarchitectlab-workspace-bootstrap` | ADLS account and container, access connector, storage credential, external location, catalog, cluster policies, secret scope |

The workspace takes roughly 10–15 minutes to create.

### 5.3 uat and prod

Repeat 5.2 with the `uat-*` stacks, then the `prod-*` stacks. Prod also needs its resource group (step 2.2) and
User Access Administrator on that resource group (step 2.4).

## 6. Verify

- Open the workspace URL (Azure portal → the Databricks workspace → **Launch workspace**).
- **Catalog:** the catalog from `catalog-config.yaml` is listed and attached to the metastore.
- **Catalog → External data:** the external location shows a successful connection test.
- **Compute → Policies:** the cluster policies from `cluster-policy-config.yaml` exist.
- **Settings → Identity and access:** `DBX_Architect_Lab_Admin` is a workspace admin.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `azure/login` fails with `AADSTS70021` / no matching federated identity | Federated credential subject doesn't match `repo:DBxArchitectLab/dbx-platform-infra-azure:environment:<env>` |
| `terragrunt init` 403 on the state blob | Service principal lacks Storage Blob Data Contributor on `adlsdbxarchitectlab`, or the role hasn't applied yet |
| `MissingSubscriptionRegistration` | Step 2.1 not done |
| `get_env` error for `ARM_SUBSCRIPTION_ID` / `DATABRICKS_*` | Secret missing in the GitHub environment the stack runs in |
| Metastore create fails: region already has a metastore | See step 3.4 |
| Storage account name already taken | Pick a different name in `adls-storage-config.yaml` (names are global) |
| Permission denied creating catalog / external location | Service principal isn't a metastore admin (step 3) |

## Running locally instead

```bash
az login
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export DATABRICKS_ACCOUNT_ID="<databricks-account-id>"
export DATABRICKS_METASTORE_ID="<metastore-id>"
export DEPLOY_SP_APPLICATION_ID="<service-principal-application-id>"

cd live/dev/workspace && terragrunt plan
```

Your user needs the same Azure roles and Databricks permissions as the service principal. If the state
storage account's firewall restricts access, add your IP to it first.
