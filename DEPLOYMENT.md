# Deployment guide

How to deploy this repository into a brand-new Azure subscription and Databricks account using the
GitHub Actions workflow (`.github/workflows/terragrunt-deploy.yml`).

Deployment order:

```
1. Repo config  →  2. Azure prerequisites  →  3. Databricks account  →  4. GitHub setup
                   (setup-azure-prerequisites.sh)                            │
5. Preflight (preflight-check.sh)  →  6. Deploy:  metastore  →  dev-workspace  →  dev-workspace-bootstrap  →  (uat, prod)
```

## Quick start

Two scripts in [`scripts/`](scripts/) cover the scripted parts. Run them from Git Bash, WSL, Linux or
macOS (not PowerShell):

```bash
# Step 2: one-time Azure setup. Idempotent; re-run it any time to fill in what's missing.
./scripts/setup-azure-prerequisites.sh --subscription <subscription-id>

# Step 3 (Databricks account console) and step 4 (GitHub secrets) are manual. The script prints the values.

# Step 5: read-only checks before each deployment
export ARM_SUBSCRIPTION_ID=<subscription-id>
export DATABRICKS_ACCOUNT_ID=<databricks-account-id>
export DATABRICKS_METASTORE_ID=<metastore-id>          # after the metastore exists
export DEPLOY_SP_APPLICATION_ID=<deployment-sp-app-id>
./scripts/preflight-check.sh                                           # everything
./scripts/preflight-check.sh dev-dbxarchitectlab-workspace-bootstrap   # one stack
```

The rest of this guide explains each step and the equivalent manual commands.

Values used throughout this guide (change them if yours differ):

| Name | Value | Defined in |
| --- | --- | --- |
| Region | `centralus` | `live/*/config.yaml`, `live/metastore/config.yaml` |
| Shared resource group (state + metastore storage) | `rg-dbx-architect-lab` | `live/root.hcl`, workflow `TF_STATE_RESOURCE_GROUP` |
| Shared storage account | `adlsdbxarchitectlab` | `live/root.hcl`, workflow `TF_STATE_STORAGE_ACCOUNT`, `live/metastore/config.yaml` |
| State container | `tfstate` | `live/root.hcl` |
| Metastore root container | `dbx` | `live/metastore/config.yaml` |
| Environment resource groups | `rg-dbx-architect-lab-{dev,uat,prod}` | `live/<env>/config.yaml` |
| GitHub repo | `DBxArchitectLab/dbx-platform-infra-azure` (owner ID `336295900`, repo ID `1398888571`) | federated credential subjects |

---

## 1. Finish the repo configuration

Edit and commit these before the first run.

- [ ] **Unique names per environment in `live/<env>/workspace-bootstrap/`.** dev, uat and prod already use
      distinct values. Keep them distinct if you change them (`preflight-check.sh` checks this):
  - `adls-storage-config.yaml` → `storage_account.name` (globally unique across Azure, 3–24 lowercase
    letters/digits)
  - `catalog-config.yaml` → `catalog.name` (unique within the metastore, which dev/uat/prod share)
  - `external-location-config.yaml` → `external_location.name` (unique within the metastore)
  - `access-connector-config.yaml` → `access_connector.name` (recommended, for clarity)
- [ ] **Metastore owner:** `metastore.owner` in `live/metastore/config.yaml` must be a principal that exists in
      the new Databricks account. Recommended: the group name `DBX_Architect_Lab_Admin` (see step 3).
- [ ] **(Optional) VNet ranges:** dev, uat and prod use `10.0.0.0/24`, `10.0.1.0/24` and `10.0.2.0/24`, so they
      can be peered later. Keep them non-overlapping if you change them.

## 2. Azure prerequisites

**Scripted:** `./scripts/setup-azure-prerequisites.sh --subscription <id>` does all of 2.1–2.4. It registers the
providers, creates the resource groups, the storage account and containers, the service principal, its role
assignments and federated credentials. Then it prints the GitHub secrets to set. It skips anything that
already exists. Use `--reset-sp-secret` to issue a new client secret and `--lock-down-storage` to make the
state storage firewall deny-by-default.

The manual equivalent follows. Run it as a user with **Owner** on the subscription.

> **Windows:** in Git Bash, set `export MSYS_NO_PATHCONV=1` first. Otherwise Git Bash rewrites `--scope
> /subscriptions/...` into a Windows path and the role assignments fail. In PowerShell, pass JSON to `az`
> through a file (`--parameters "@file.json"`), not inline.

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
az group create -n rg-dbx-architect-lab-prod -l "$REGION"
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

# Give yourself data access so you can run Terragrunt locally (the state backend uses Entra ID auth).
az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Storage Blob Data Contributor" --scope "$SA_ID"

# Management-plane commands don't need the data role, so they work straight away.
az storage container-rm create --storage-account adlsdbxarchitectlab -g rg-dbx-architect-lab -n tfstate
az storage container-rm create --storage-account adlsdbxarchitectlab -g rg-dbx-architect-lab -n dbx
```

> Subscription Owner/Contributor don't include blob data access, so without that grant a local
> `terragrunt init` returns 403. The role takes a few minutes to apply.

### 2.4 Service principal for GitHub Actions

```bash
SP_NAME="sp-dbx-platform-infra"
az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "/subscriptions/$SUB"
# Save appId (SP_CLIENT_ID), password (SP_CLIENT_SECRET) and tenant (AZURE_TENANT_ID).

APP_ID="<appId from the output>"

# workspace-bootstrap creates a role assignment on its ADLS account. Include every environment, prod too.
for rg in rg-dbx-architect-lab-dev rg-dbx-architect-lab-uat rg-dbx-architect-lab-prod; do
  az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
    --scope "/subscriptions/$SUB/resourceGroups/$rg"
done

# Read/write Terraform state with Entra ID auth (use_azuread_auth = true).
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID"
```

`Contributor` on the subscription also covers the workflow's firewall steps (adding and removing the
runner IP on `adlsdbxarchitectlab`).

**Federated credentials.** The service principal needs both a federated credential and a client secret.
The workflow's `azure/login` step signs in the Azure CLI with GitHub OIDC (no secret). The firewall steps
and the workspace-level Databricks provider in `workspace-bootstrap` (`auth_type = "azure-cli"`) use that
session. azurerm, the state backend and the account-level Databricks provider use the client secret
(`ARM_CLIENT_SECRET`). Add one federated credential per GitHub environment.

The subject must match what this repo's OIDC token carries exactly. This repo's tokens use the ID-based
form `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:<env>`. Credentials made with the plain form
(`repo:DBxArchitectLab/dbx-platform-infra:...`) stopped matching after the repo was renamed to
`dbx-platform-infra-azure`. Look up the IDs with
`gh api repos/DBxArchitectLab/dbx-platform-infra-azure --jq '.owner.id, .id'`.

```bash
for env in dev uat prod; do
  cat > fic.json <<JSON
{ "name": "github-dbx-platform-infra-azure-$env",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:DBxArchitectLab@336295900/dbx-platform-infra-azure@1398888571:environment:$env",
  "audiences": ["api://AzureADTokenExchange"] }
JSON
  az ad app federated-credential create --id "$APP_ID" --parameters @fic.json
done
rm fic.json
```

If the `azure/login` error shows a different subject, copy it from the error message into the credential.
Delete credentials left over from the old repo name in **Entra ID → App registrations →
sp-dbx-platform-infra → Certificates & secrets → Federated credentials**.

**Client secret hygiene.** `create-for-rbac` and `credential reset` print the secret once. Put it straight into
the GitHub secret and don't keep it in notes or chat. If it leaks, rotate it with
`az ad app credential reset --id "$APP_ID" --append`, update `SP_CLIENT_SECRET` in every GitHub
environment, then delete the old credential.

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
   | `DATABRICKS_METASTORE_ID` | metastore ID (set after step 6.1 or 3.4; any placeholder until then) |

   The `metastore` stack runs in the `dev` environment.

## 5. Preflight

Before each `apply`, run the read-only checks for the stack you're about to deploy. They use your own az login,
so the state-access and Databricks account checks test *your* permissions, not the service principal's.
The service principal's User Access Administrator roles are checked when `DEPLOY_SP_APPLICATION_ID` is set.

```bash
./scripts/preflight-check.sh metastore
./scripts/preflight-check.sh dev-dbxarchitectlab-workspace
./scripts/preflight-check.sh dev-dbxarchitectlab-workspace-bootstrap
```

It checks tool versions against the workflow, required environment variables, subscription, provider
registration, state storage (HNS, firewall, Entra ID data access, containers), resource groups, the
service principal's User Access Administrator, name uniqueness and global storage-name availability, and
the Databricks account. For the account it checks API access, the `DBX_Architect_Lab_Admin` group, the
regional metastore, `DATABRICKS_METASTORE_ID` and the metastore owner. It exits non-zero on any failure.

## 6. Deploy

Go to **Actions → Terragrunt Deploy Stacks → Run workflow**, choose a **stack** and an **action**. For
each stack, run `plan` first, review the log, then run `apply`. The run is named after the action and
stack (for example `apply dev-dbxarchitectlab-workspace-bootstrap`). Its first step, **Show deployment
selection**, lists the action, stack, path, GitHub environment and commit on the run's summary page.
`apply` and `destroy` runs also get a warning there, because they don't ask for confirmation.

### 6.1 Metastore (once per region)

| Stack | Action |
| --- | --- |
| `metastore` | `plan`, then `apply` |

Then copy the metastore ID from the account console (**Catalog → your metastore**) or from the
`metastore_id` output at the end of the apply log. Set it as `DATABRICKS_METASTORE_ID` in the `dev`,
`uat` and `prod` environments. They share the metastore because they're in the same region.

### 6.2 dev

| Order | Stack | Creates |
| --- | --- | --- |
| 1 | `dev-dbxarchitectlab-workspace` | VNet, subnets, NSG, private DNS, private endpoints, workspace, metastore assignment, admin group assignment |
| 2 | `dev-dbxarchitectlab-workspace-bootstrap` | ADLS account and container, access connector, storage credential, external location, catalog (bound to this workspace only), workspace default catalog, cluster policies, secret scope |

The workspace takes roughly 10–15 minutes to create.

### 6.3 uat and prod

Repeat 6.2 with the `uat-*` stacks, then the `prod-*` stacks. Run `preflight-check.sh` for each stack first.
Each environment needs its own resource group (step 2.2) and User Access Administrator on it (step 2.4).
prod was missed once.

## 7. Verify

- Open the workspace URL (Azure portal → the Databricks workspace → **Launch workspace**).
- **Catalog:** the catalog from `catalog-config.yaml` is listed. Under **Details → Workspaces** it shows
  only this environment's workspace. It isn't visible in the other environments' workspaces.
- **Settings → Workspace admin → Advanced → Default catalog:** set to that catalog.
- **Catalog → External data:** the external location shows a successful connection test.
- **Compute → Policies:** the cluster policies from `cluster-policy-config.yaml` exist.
- **Settings → Identity and access:** `DBX_Architect_Lab_Admin` is a workspace admin.

### Drop the automatic workspace catalog (once per workspace)

Databricks creates a workspace catalog named after each workspace (`dbw_dbx_architect_lab_dev`, `_uat`,
`_prod`), bound to that workspace. Terraform doesn't manage it. After the bootstrap `apply` has moved the
default catalog, drop it from a SQL editor **in that workspace**, as a metastore admin:

```sql
DROP CATALOG IF EXISTS dbw_dbx_architect_lab_dev CASCADE;   -- _uat in uat, _prod in prod
```

`CASCADE` deletes everything in it, so check first that nobody has created tables there. It isn't recreated.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `azure/login` fails with `AADSTS70021` / no matching federated identity | Federated credential subject doesn't match the token. This repo uses `repo:DBxArchitectLab@336295900/dbx-platform-infra-azure@1398888571:environment:<env>`. After a repo rename, add credentials for the new subject (step 2.4) |
| `terragrunt init` 403 on the state blob | The identity lacks Storage Blob Data Contributor on `adlsdbxarchitectlab` (Owner/Contributor isn't enough), the role hasn't applied yet, or the storage firewall blocks your IP |
| `MissingSubscriptionRegistration` | Step 2.1 not done |
| Role assignment fails with a path like `C:/Program Files/Git/subscriptions/...` | Git Bash path conversion; `export MSYS_NO_PATHCONV=1` |
| `az ... --parameters` fails to parse JSON on Windows | Pass JSON through a file (`@file.json`) |
| workspace-bootstrap fails creating the access connector's role assignment (`AuthorizationFailed`) | Service principal lacks User Access Administrator on that environment's resource group (step 2.4, including prod) |
| Metastore apply fails on the storage root | The `dbx` container doesn't exist in `adlsdbxarchitectlab` |
| `get_env` error for `ARM_SUBSCRIPTION_ID` / `DATABRICKS_*` | Secret missing in the GitHub environment the stack runs in |
| Metastore create fails: region already has a metastore | See step 3.4 |
| Storage account name already taken | Pick a different name in `adls-storage-config.yaml` (names are global) |
| Permission denied creating catalog / external location | Service principal isn't a metastore admin (step 3) |
| `dbxarchitectlab_dev` isn't visible from the uat or prod workspace (and so on) | Expected: each catalog is isolated to its own workspace |

## Running locally instead

```bash
az login
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export DATABRICKS_ACCOUNT_ID="<databricks-account-id>"
export DATABRICKS_METASTORE_ID="<metastore-id>"
export DEPLOY_SP_APPLICATION_ID="<service-principal-application-id>"

cd live/dev/workspace && terragrunt plan
```

Your user needs the same Azure roles and Databricks permissions as the service principal. That includes
**Storage Blob Data Contributor** on `adlsdbxarchitectlab`. If the state storage account's firewall restricts
access, add your IP to it first. `./scripts/preflight-check.sh <stack>` checks all of this.

Use the Terragrunt version from the workflow (`0.99.4`). Older 0.x releases differ in CLI flags and
`root.hcl` handling.
