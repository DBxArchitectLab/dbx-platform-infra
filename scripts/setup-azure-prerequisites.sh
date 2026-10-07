#!/usr/bin/env bash
# One-time Azure setup for this repo (DEPLOYMENT.md steps 2.1–2.4). Safe to re-run: every step checks
# what already exists and skips it.
#
#   ./scripts/setup-azure-prerequisites.sh --subscription <subscription-id> [options]
#
# Options:
#   --subscription ID      Target subscription (required; or set ARM_SUBSCRIPTION_ID)
#   --region NAME          Azure region (default: centralus)
#   --environments "LIST"  Environments to prepare (default: "dev uat prod")
#   --sp-name NAME         Deployment service principal display name (default: sp-dbx-platform-infra)
#   --github-repo O/R      GitHub repo for federated credentials (default: taken from the git remote)
#   --github-ids OID:RID   GitHub owner and repo IDs for the OIDC subject (default: looked up with gh/curl)
#   --plain-oidc-subject   Use "repo:owner/repo:environment:<env>" instead of the ID-based subject
#                          "repo:owner@OID/repo@RID:environment:<env>" this repo's tokens carry
#   --reset-sp-secret     Create a new client secret even if the service principal already exists
#   --lock-down-storage    Set the state storage firewall to deny by default, allowing only your current IP
#                          (the GitHub workflow adds and removes the runner IP itself)
#   -h, --help             Show this help
#
# Run as a user with Owner on the subscription (role assignments need it) and permission to create
# app registrations in Entra ID. Databricks account steps (DEPLOYMENT.md step 3) stay manual; the script
# prints them at the end.

set -euo pipefail

# Git Bash on Windows rewrites arguments that start with "/" (e.g. /subscriptions/...) into Windows paths,
# which breaks every --scope argument. Turn that off.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# Must match live/root.hcl and the workflow's TF_STATE_* variables.
STATE_RG="rg-dbx-architect-lab"
STATE_SA="adlsdbxarchitectlab"
STATE_CONTAINER="tfstate"
METASTORE_CONTAINER="dbx"
ENV_RG_PREFIX="rg-dbx-architect-lab"

SUB="${ARM_SUBSCRIPTION_ID:-}"
REGION="centralus"
ENVIRONMENTS="dev uat prod"
SP_NAME="sp-dbx-platform-infra"
GITHUB_REPO=""
GITHUB_IDS=""
PLAIN_SUBJECT=false
RESET_SECRET=false
LOCK_DOWN=false

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUB="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --environments) ENVIRONMENTS="$2"; shift 2 ;;
    --sp-name) SP_NAME="$2"; shift 2 ;;
    --github-repo) GITHUB_REPO="$2"; shift 2 ;;
    --github-ids) GITHUB_IDS="$2"; shift 2 ;;
    --plain-oidc-subject) PLAIN_SUBJECT=true; shift ;;
    --reset-sp-secret) RESET_SECRET=true; shift ;;
    --lock-down-storage) LOCK_DOWN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
info() { printf '  • %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# az on Windows emits CRLF in tsv output; strip it so comparisons work.
az_tsv() { az "$@" -o tsv | tr -d '\r'; }

# Retries a command while a fresh role assignment or Entra object propagates (often 1–5 minutes).
retry() {
  local attempts=$1; shift
  local i
  for ((i = 1; i <= attempts; i++)); do
    if "$@"; then return 0; fi
    warn "attempt $i/$attempts failed; waiting 30s for propagation..."
    sleep 30
  done
  return 1
}

# Creates a role assignment unless one already exists.
ensure_role() {
  local object_id=$1 principal_type=$2 role=$3 scope=$4
  local count
  count=$(az_tsv role assignment list --assignee "$object_id" --role "$role" --scope "$scope" --query "length(@)")
  if [[ "$count" != "0" ]]; then
    ok "$role already assigned on ${scope##*/}"
    return
  fi
  retry 5 az role assignment create --assignee-object-id "$object_id" \
    --assignee-principal-type "$principal_type" --role "$role" --scope "$scope" -o none \
    || die "could not assign $role on $scope"
  ok "assigned $role on ${scope##*/}"
}

# ---------------------------------------------------------------------------------------------------------
[[ -n "$SUB" ]] || { usage; die "--subscription (or ARM_SUBSCRIPTION_ID) is required"; }
command -v az >/dev/null || die "Azure CLI (az) not found"

if [[ -z "$GITHUB_REPO" ]]; then
  remote=$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null || true)
  GITHUB_REPO=$(sed -E 's#^.*github\.com[:/]##; s#\.git$##' <<<"$remote")
  [[ "$GITHUB_REPO" == */* ]] || die "could not read the GitHub repo from git remote; pass --github-repo owner/repo"
fi

# This repo's GitHub OIDC tokens use the ID-based subject (repo:owner@id/repo@id:...), which survives
# renames. After the rename from dbx-platform-infra, credentials with the plain subject stopped matching.
if [[ "$PLAIN_SUBJECT" == true ]]; then
  OIDC_REPO="$GITHUB_REPO"
else
  if [[ -z "$GITHUB_IDS" ]]; then
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
      GITHUB_IDS=$(gh api "repos/$GITHUB_REPO" --jq '"\(.owner.id):\(.id)"' 2>/dev/null | tr -d '\r' || true)
    fi
    if [[ -z "$GITHUB_IDS" ]]; then
      # Works for public repos without auth.
      json=$(curl -s --max-time 10 "https://api.github.com/repos/$GITHUB_REPO" || true)
      owner_id=$(sed -n '/"owner"/,/}/s/^ *"id": *\([0-9]*\).*/\1/p' <<<"$json" | head -1)
      repo_id=$(sed -n 's/^  "id": *\([0-9]*\).*/\1/p' <<<"$json" | head -1)
      [[ -n "$owner_id" && -n "$repo_id" ]] && GITHUB_IDS="$owner_id:$repo_id"
    fi
    [[ -n "$GITHUB_IDS" ]] || die "could not look up GitHub IDs for $GITHUB_REPO (private repo?). Run 'gh auth login', or pass --github-ids OWNER_ID:REPO_ID (e.g. 336295900:1398888571)"
  fi
  OIDC_REPO="${GITHUB_REPO%%/*}@${GITHUB_IDS%%:*}/${GITHUB_REPO#*/}@${GITHUB_IDS#*:}"
fi

step "Signing in to subscription $SUB"
az account show -o none 2>/dev/null || az login -o none
az account set --subscription "$SUB"
TENANT_ID=$(az_tsv account show --query tenantId)
ME_ID=$(az_tsv ad signed-in-user show --query id 2>/dev/null || true)
[[ -n "$ME_ID" ]] || die "sign in as a user (not a service principal) so the script can grant you storage data access"
ok "tenant $TENANT_ID, user object $ME_ID"
info "GitHub OIDC subject prefix: repo:$OIDC_REPO"

# --- 2.1 Resource providers -------------------------------------------------------------------------------
# live/root.hcl sets resource_provider_registrations = "none", so Terraform won't register these.
step "Registering resource providers"
for ns in Microsoft.Databricks Microsoft.Network Microsoft.Storage Microsoft.ManagedIdentity; do
  state=$(az_tsv provider show --namespace "$ns" --query registrationState)
  if [[ "$state" == "Registered" ]]; then
    ok "$ns"
  else
    info "registering $ns (current: $state)..."
    az provider register --namespace "$ns" --wait -o none
    ok "$ns registered"
  fi
done

# --- 2.2 Resource groups ----------------------------------------------------------------------------------
step "Creating resource groups"
for rg in "$STATE_RG" $(for e in $ENVIRONMENTS; do echo "$ENV_RG_PREFIX-$e"; done); do
  if [[ "$(az_tsv group exists -n "$rg")" == "true" ]]; then
    ok "$rg exists"
  else
    az group create -n "$rg" -l "$REGION" -o none
    ok "$rg created"
  fi
done

# --- 2.3 State + metastore storage account ----------------------------------------------------------------
step "State and metastore storage account ($STATE_SA)"
if az storage account show -n "$STATE_SA" -g "$STATE_RG" -o none 2>/dev/null; then
  hns=$(az_tsv storage account show -n "$STATE_SA" -g "$STATE_RG" --query isHnsEnabled)
  [[ "$hns" == "true" ]] || die "$STATE_SA exists without hierarchical namespace. The metastore root needs ADLS Gen2, and HNS can only be set when the account is created."
  ok "$STATE_SA exists (HNS enabled)"
else
  avail=$(az_tsv storage account check-name -n "$STATE_SA" --query nameAvailable)
  [[ "$avail" == "true" ]] || die "storage account name $STATE_SA is taken globally; change it in live/root.hcl, the workflow and live/metastore/config.yaml"
  az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$REGION" \
    --sku Standard_LRS --kind StorageV2 --hns true \
    --min-tls-version TLS1_2 --allow-blob-public-access false -o none
  ok "$STATE_SA created"
fi
SA_ID=$(az_tsv storage account show -n "$STATE_SA" -g "$STATE_RG" --query id)

# If the firewall is already deny-by-default, data-plane calls from this machine need its IP allowed.
MY_IP=$(curl -s --max-time 10 https://api.ipify.org || true)
default_action=$(az_tsv storage account show -n "$STATE_SA" -g "$STATE_RG" --query networkRuleSet.defaultAction)
if [[ "$default_action" == "Deny" || "$LOCK_DOWN" == true ]]; then
  [[ -n "$MY_IP" ]] || die "could not detect your public IP to allow it on the storage firewall"
  az storage account network-rule add -n "$STATE_SA" -g "$STATE_RG" --ip-address "$MY_IP" -o none
  ok "allowed your IP $MY_IP on the $STATE_SA firewall"
fi
if [[ "$LOCK_DOWN" == true && "$default_action" != "Deny" ]]; then
  az storage account update -n "$STATE_SA" -g "$STATE_RG" --default-action Deny --bypass AzureServices -o none
  ok "firewall default action set to Deny"
fi

ensure_role "$ME_ID" User "Storage Blob Data Contributor" "$SA_ID"

# Management-plane (container-rm) calls don't depend on the data role or firewall, which take minutes to apply.
# The data-plane "container exists" also reports false when access is denied, which hides the real problem.
for c in "$STATE_CONTAINER" "$METASTORE_CONTAINER"; do
  if [[ "$(az_tsv storage container-rm exists --storage-account "$STATE_SA" -g "$STATE_RG" -n "$c")" == "true" ]]; then
    ok "container $c exists"
  else
    az storage container-rm create --storage-account "$STATE_SA" -g "$STATE_RG" -n "$c" -o none
    ok "container $c created"
  fi
done

# --- 2.4 Deployment service principal ---------------------------------------------------------------------
step "Deployment service principal ($SP_NAME)"
APP_ID=$(az_tsv ad app list --display-name "$SP_NAME" --query "[0].appId")
NEW_SECRET=""
if [[ -z "$APP_ID" ]]; then
  APP_ID=$(az_tsv ad app create --display-name "$SP_NAME" --query appId)
  ok "app registration created ($APP_ID)"
  RESET_SECRET=true
else
  ok "app registration exists ($APP_ID)"
fi
SP_OBJECT_ID=$(az_tsv ad sp list --filter "appId eq '$APP_ID'" --query "[0].id")
if [[ -z "$SP_OBJECT_ID" ]]; then
  SP_OBJECT_ID=$(retry 5 az_tsv ad sp create --id "$APP_ID" --query id) || die "could not create the service principal"
  ok "service principal created ($SP_OBJECT_ID)"
else
  ok "service principal exists ($SP_OBJECT_ID)"
fi
if [[ "$RESET_SECRET" == true ]]; then
  NEW_SECRET=$(az_tsv ad app credential reset --id "$APP_ID" --display-name "github-actions" --years 1 --append --query password)
  ok "client secret created (shown once at the end)"
else
  info "keeping existing client secret (use --reset-sp-secret to create a new one)"
fi

# Contributor: create resources and edit the state storage firewall from the workflow.
ensure_role "$SP_OBJECT_ID" ServicePrincipal "Contributor" "/subscriptions/$SUB"
# workspace-bootstrap assigns Storage Blob Data Contributor to the access connector on its ADLS account.
for e in $ENVIRONMENTS; do
  ensure_role "$SP_OBJECT_ID" ServicePrincipal "User Access Administrator" "/subscriptions/$SUB/resourceGroups/$ENV_RG_PREFIX-$e"
done
# Terraform state is read with Entra ID auth (use_azuread_auth = true).
ensure_role "$SP_OBJECT_ID" ServicePrincipal "Storage Blob Data Contributor" "$SA_ID"

# Federated credentials: azure/login in the workflow signs in with GitHub OIDC per GitHub environment.
step "Federated credentials for $GITHUB_REPO"
existing=$(az_tsv ad app federated-credential list --id "$APP_ID" --query "[].subject")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
for e in $ENVIRONMENTS; do
  subject="repo:$OIDC_REPO:environment:$e"
  if grep -qxF "$subject" <<<"$existing"; then
    ok "$subject"
    continue
  fi
  # Pass JSON through a file: inline JSON quoting breaks between bash, Git Bash and az.cmd on Windows.
  cat >"$tmp" <<EOF
{
  "name": "github-${GITHUB_REPO#*/}-$e",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$subject",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
  az ad app federated-credential create --id "$APP_ID" --parameters "@$tmp" -o none
  ok "created $subject"
done
# Credentials for other subjects (e.g. from before the repo rename) no longer match any token.
stale=$(grep -vF "repo:$OIDC_REPO:" <<<"$existing" | grep . || true)
if [[ -n "$stale" ]]; then
  warn "these federated credentials don't match the current repo and can be deleted:"
  sed 's/^/      /' <<<"$stale"
fi

# --- Summary ----------------------------------------------------------------------------------------------
step "Done. Next steps"
cat <<EOF

GitHub → Settings → Environments → (${ENVIRONMENTS// /, }) → add these secrets to each:

  AZURE_CLIENT_ID          $APP_ID
  AZURE_CLIENT_SECRET      ${NEW_SECRET:-<unchanged; existing secret>}
  AZURE_TENANT_ID          $TENANT_ID
  AZURE_SUBSCRIPTION_ID    $SUB
  DATABRICKS_ACCOUNT_ID    <from https://accounts.azuredatabricks.net, user menu>
  DATABRICKS_METASTORE_ID  <after the metastore stack is applied; any placeholder until then>

Databricks account console (manual, DEPLOYMENT.md step 3):
  1. User management → Service principals → Add → application ID $APP_ID → turn on "Account admin".
  2. User management → Groups → create DBX_Architect_Lab_Admin; add the service principal and yourself.
  3. Catalog → check for an existing metastore in $REGION (one per region per account).

Then check everything with:
  ./scripts/preflight-check.sh
EOF
if [[ -n "$NEW_SECRET" ]]; then
  warn "The client secret above is shown only once. Store it in GitHub now; it expires in 1 year."
fi
