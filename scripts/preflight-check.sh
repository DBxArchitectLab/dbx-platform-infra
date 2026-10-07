#!/usr/bin/env bash
# Read-only checks to run before a deployment, locally or in CI. Each check maps to a failure we hit while
# setting up this repo. Nothing is created or changed.
#
#   ./scripts/preflight-check.sh [stack]
#
#   stack  A workflow stack name (metastore, dev-dbxarchitectlab-workspace, ...) or a path (live/dev/workspace).
#          Omit it to check the shared prerequisites and every environment.
#
# Reads the same environment variables as Terragrunt:
#   ARM_SUBSCRIPTION_ID       required
#   DATABRICKS_ACCOUNT_ID     required
#   DATABRICKS_METASTORE_ID   required for */workspace and */workspace-bootstrap
#   DEPLOY_SP_APPLICATION_ID  required for */workspace-bootstrap
#
# Exit code: 0 when there are no failures (warnings allowed), 1 otherwise.

set -uo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="$ROOT/.github/workflows/terragrunt-deploy.yml"

# Must match live/root.hcl.
STATE_RG="rg-dbx-architect-lab"
STATE_SA="adlsdbxarchitectlab"
STATE_CONTAINER="tfstate"
ADMIN_GROUP="DBX_Architect_Lab_Admin"
# Entra application ID of the Azure Databricks first-party app; used to get Databricks API tokens.
DATABRICKS_RESOURCE="2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
ACCOUNTS_HOST="https://accounts.azuredatabricks.net"

FAILS=0
WARNS=0
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; WARNS=$((WARNS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
hint() { printf '       ↳ %s\n' "$*"; }

az_tsv() { az "$@" -o tsv 2>/dev/null | tr -d '\r'; }

# First value of "key:" in a YAML file, quotes and trailing comments removed. Enough for these flat configs.
yaml_get() {
  sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//' | tr -d '\r'
}

# --- Resolve which stacks to check -----------------------------------------------------------------------
STACK="${1:-all}"
case "$STACK" in
  all) STACK_PATH="" ;;
  metastore) STACK_PATH="live/metastore" ;;
  dev-*|uat-*|prod-*)
    env=${STACK%%-*}
    [[ "$STACK" == *-workspace-bootstrap ]] && STACK_PATH="live/$env/workspace-bootstrap" || STACK_PATH="live/$env/workspace" ;;
  live/*) STACK_PATH="${STACK%/}" ;;
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  *) echo "Unknown stack: $STACK" >&2; exit 2 ;;
esac
if [[ -n "$STACK_PATH" && ! -f "$ROOT/$STACK_PATH/terragrunt.hcl" ]]; then
  echo "No terragrunt.hcl in $STACK_PATH" >&2; exit 2
fi

if [[ -z "$STACK_PATH" ]]; then
  ENVS=$(cd "$ROOT/live" && for d in */; do [[ -f "$d/config.yaml" && -d "$d/workspace" ]] && echo "${d%/}"; done)
  NEEDS_METASTORE_ID=true; NEEDS_SP_ID=true; CHECK_METASTORE_STACK=true
else
  ENVS=$(sed -n 's#^live/\([a-z]*\)/workspace.*#\1#p' <<<"$STACK_PATH")
  NEEDS_METASTORE_ID=false; NEEDS_SP_ID=false; CHECK_METASTORE_STACK=false
  [[ "$STACK_PATH" == */workspace* ]] && NEEDS_METASTORE_ID=true
  [[ "$STACK_PATH" == */workspace-bootstrap ]] && NEEDS_SP_ID=true
  [[ "$STACK_PATH" == live/metastore ]] && CHECK_METASTORE_STACK=true
fi
echo "Preflight for: ${STACK_PATH:-all stacks}"

# --- Tools -----------------------------------------------------------------------------------------------
section "Tools"
want_tf=$(sed -n 's/^ *terraform_version: *//p' "$WORKFLOW" | tr -d '\r"')
want_tg=$(sed -n 's/^ *TG_VERSION="\(.*\)"/\1/p' "$WORKFLOW" | tr -d '\r')
for tool in az terraform terragrunt; do
  command -v "$tool" >/dev/null || { fail "$tool not found on PATH"; continue; }
  case "$tool" in
    az) pass "az $(az version --query '"azure-cli"' -o tsv 2>/dev/null | tr -d '\r')" ;;
    terraform)
      v=$(terraform version 2>/dev/null | sed -n '1s/^Terraform v//p' | tr -d '\r')
      [[ "$v" == "$want_tf" ]] && pass "terraform $v" || warn "terraform $v (CI uses $want_tf; lock files may differ)" ;;
    terragrunt)
      v=$(terragrunt --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
      [[ "$v" == "$want_tg" ]] && pass "terragrunt $v" || warn "terragrunt $v (CI uses $want_tg)" ;;
  esac
done
command -v az >/dev/null || { echo; echo "Azure CLI is required for the remaining checks."; exit 1; }

# --- Environment variables -------------------------------------------------------------------------------
section "Environment variables"
check_var() {
  local name=$1 required=$2
  if [[ -n "${!name:-}" ]]; then
    [[ "${!name}" =~ ^[0-9a-f-]{36}$ ]] && pass "$name set" || warn "$name set but isn't a GUID: ${!name}"
  elif [[ "$required" == true ]]; then
    fail "$name not set (Terragrunt get_env fails without it)"
  fi
}
check_var ARM_SUBSCRIPTION_ID true
check_var DATABRICKS_ACCOUNT_ID true
check_var DATABRICKS_METASTORE_ID "$NEEDS_METASTORE_ID"
check_var DEPLOY_SP_APPLICATION_ID "$NEEDS_SP_ID"

# --- Azure sign-in ---------------------------------------------------------------------------------------
section "Azure sign-in"
if ! az account show -o none 2>/dev/null; then
  fail "not signed in to Azure CLI"; hint "az login"
  echo; echo "Result: $FAILS failed, $WARNS warnings"; exit 1
fi
cur_sub=$(az_tsv account show --query id)
user_type=$(az_tsv account show --query user.type)
user_name=$(az_tsv account show --query user.name)
pass "signed in as $user_name ($user_type)"
if [[ -n "${ARM_SUBSCRIPTION_ID:-}" && "$cur_sub" != "$ARM_SUBSCRIPTION_ID" ]]; then
  fail "az is on subscription $cur_sub but ARM_SUBSCRIPTION_ID is $ARM_SUBSCRIPTION_ID"
  hint "az account set --subscription $ARM_SUBSCRIPTION_ID"
else
  pass "subscription $cur_sub"
fi
SUB="${ARM_SUBSCRIPTION_ID:-$cur_sub}"

# --- Resource providers ----------------------------------------------------------------------------------
section "Resource providers (root.hcl disables auto-registration)"
for ns in Microsoft.Databricks Microsoft.Network Microsoft.Storage Microsoft.ManagedIdentity; do
  s=$(az_tsv provider show --namespace "$ns" --subscription "$SUB" --query registrationState)
  [[ "$s" == "Registered" ]] && pass "$ns" || { fail "$ns is ${s:-unknown} (MissingSubscriptionRegistration)"; hint "az provider register --namespace $ns --wait"; }
done

# --- Terraform state storage -----------------------------------------------------------------------------
section "Terraform state storage ($STATE_SA)"
if ! az storage account show -n "$STATE_SA" -g "$STATE_RG" --subscription "$SUB" -o none 2>/dev/null; then
  fail "$STATE_SA not found in $STATE_RG"; hint "./scripts/setup-azure-prerequisites.sh"
else
  [[ "$(az_tsv storage account show -n "$STATE_SA" -g "$STATE_RG" --subscription "$SUB" --query isHnsEnabled)" == "true" ]] \
    && pass "hierarchical namespace enabled" || fail "hierarchical namespace disabled; the metastore abfss:// root needs ADLS Gen2"

  default_action=$(az_tsv storage account show -n "$STATE_SA" -g "$STATE_RG" --subscription "$SUB" --query networkRuleSet.defaultAction)
  if [[ "$default_action" == "Deny" ]]; then
    my_ip=$(curl -s --max-time 10 https://api.ipify.org || true)
    allowed=$(az_tsv storage account network-rule list -n "$STATE_SA" -g "$STATE_RG" --subscription "$SUB" \
      --query "ipRules[?ipAddressOrRange=='$my_ip'] | length(@)")
    if [[ -n "${GITHUB_ACTIONS:-}" || "$allowed" == "1" ]]; then
      pass "firewall is deny-by-default; this machine is allowed"
    else
      fail "firewall is deny-by-default and your IP ${my_ip:-?} isn't allowed (state access returns 403)"
      hint "az storage account network-rule add -n $STATE_SA -g $STATE_RG --ip-address ${my_ip:-<your-ip>}"
    fi
  else
    pass "firewall default action: ${default_action:-Allow}"
  fi

  # Exercises the same path as the azurerm backend: Entra ID auth + data-plane role + firewall.
  if az storage blob list --account-name "$STATE_SA" -c "$STATE_CONTAINER" --auth-mode login \
       --num-results 1 -o none 2>/dev/null; then
    pass "can list blobs in $STATE_CONTAINER with Entra ID auth"
  else
    fail "$user_name can't read container $STATE_CONTAINER with Entra ID auth (terragrunt init would fail with 403)"
    hint "needs Storage Blob Data Contributor on $STATE_SA (Contributor/Owner isn't enough; wait ~5 min after granting)"
    hint "az role assignment create --assignee-object-id <your-object-id> --role \"Storage Blob Data Contributor\" --scope <$STATE_SA resource id>"
  fi

  if [[ "$CHECK_METASTORE_STACK" == true ]]; then
    root=$(yaml_get "$ROOT/live/metastore/config.yaml" storage_root)
    mcontainer=$(sed -n 's#^abfss://\([^@]*\)@.*#\1#p' <<<"$root")
    # Management-plane check: the data-plane "container exists" reports false when access is denied.
    exists=$(az_tsv storage container-rm exists --storage-account "$STATE_SA" -g "$STATE_RG" --subscription "$SUB" -n "$mcontainer")
    [[ "$exists" == "true" ]] && pass "metastore root container $mcontainer exists" || fail "metastore root container ${mcontainer:-?} missing"
  fi
fi

# --- Per-environment checks ------------------------------------------------------------------------------
declare -A SEEN
for env in $ENVS; do
  cfg="$ROOT/live/$env/config.yaml"
  bs="$ROOT/live/$env/workspace-bootstrap"
  section "Environment: $env"

  rg=$(yaml_get "$cfg" resource_group_name)
  if [[ "$(az_tsv group exists -n "$rg" --subscription "$SUB")" == "true" ]]; then
    pass "resource group $rg exists"
  else
    fail "resource group $rg missing (the workspace stack reads it, it doesn't create it)"
    hint "az group create -n $rg -l $(yaml_get "$cfg" region)"
  fi

  # The deployment identity needs User Access Administrator (or Owner) on the RG for the access connector's
  # role assignment in workspace-bootstrap. prod was missed the first time.
  sp_id="${DEPLOY_SP_APPLICATION_ID:-}"
  if [[ -n "$sp_id" ]]; then
    roles=$(az_tsv role assignment list --assignee "$sp_id" --include-inherited --all \
      --query "[?scope=='/subscriptions/$SUB/resourceGroups/$rg' || scope=='/subscriptions/$SUB'].roleDefinitionName")
    if grep -qxE "Owner|User Access Administrator" <<<"$roles"; then
      pass "deployment SP can assign roles in $rg"
    else
      fail "deployment SP lacks User Access Administrator on $rg"
      hint "az role assignment create --assignee $sp_id --role \"User Access Administrator\" --scope /subscriptions/$SUB/resourceGroups/$rg"
    fi
  fi

  # Names that must be unique: storage accounts across all of Azure, UC objects across the shared metastore,
  # VNet ranges if environments are ever peered.
  sa=$(yaml_get "$bs/adls-storage-config.yaml" name)
  catalog=$(yaml_get "$bs/catalog-config.yaml" name)
  extloc=$(yaml_get "$bs/external-location-config.yaml" name)
  cidr=$(sed -n 's/^[[:space:]]*vnet_cidr:.*"\(.*\)".*/\1/p' "$cfg" | tr -d '\r')
  for pair in "storage account:$sa" "catalog:$catalog" "external location:$extloc" "VNet CIDR:$cidr"; do
    kind=${pair%%:*}; val=${pair#*:}
    if [[ -n "${SEEN[$kind|$val]:-}" ]]; then
      [[ "$kind" == "VNet CIDR" ]] && warn "$kind $val also used by ${SEEN[$kind|$val]} (fine unless peered)" \
                                   || fail "$kind $val also used by ${SEEN[$kind|$val]}; must be unique"
    fi
    SEEN[$kind|$val]=$env
  done

  if [[ "$(az_tsv storage account check-name -n "$sa" --query nameAvailable)" == "true" ]]; then
    pass "storage account name $sa available"
  elif az storage account show -n "$sa" -g "$rg" --subscription "$SUB" -o none 2>/dev/null; then
    pass "storage account $sa already exists in $rg"
  else
    fail "storage account name $sa is taken by someone else; change it in adls-storage-config.yaml"
  fi
done

# --- Databricks account ----------------------------------------------------------------------------------
section "Databricks account"
if [[ -z "${DATABRICKS_ACCOUNT_ID:-}" ]]; then
  warn "skipped (DATABRICKS_ACCOUNT_ID not set)"
else
  acct_api="$ACCOUNTS_HOST/api/2.0/accounts/$DATABRICKS_ACCOUNT_ID"
  dbx_get() { az rest --method get --resource "$DATABRICKS_RESOURCE" --url "$1" --query "$2" -o tsv 2>&1 | tr -d '\r'; }

  if ! out=$(dbx_get "$acct_api/scim/v2/Groups?filter=displayName%20eq%20%22$ADMIN_GROUP%22" "Resources[].id"); then
    fail "can't call the account API as $user_name"
    hint "the signed-in identity must be a Databricks account admin; check DATABRICKS_ACCOUNT_ID"
    hint "$(head -1 <<<"$out")"
  else
    pass "account API reachable; signed-in identity is an account admin"
    [[ -n "$out" ]] && pass "group $ADMIN_GROUP exists" || fail "group $ADMIN_GROUP not found in the account (workspace admin assignment and metastore owner need it)"

    region=$(yaml_get "$ROOT/live/metastore/config.yaml" region)
    mname=$(yaml_get "$ROOT/live/metastore/config.yaml" name)
    ms=$(dbx_get "$acct_api/metastores" "metastores[?region=='$region'].[metastore_id,name,owner]")
    if [[ -z "$ms" ]]; then
      [[ "$CHECK_METASTORE_STACK" == true ]] && pass "no metastore in $region yet; the metastore stack can create one" \
        || fail "no metastore in $region; apply the metastore stack first"
    else
      read -r ms_id ms_name ms_owner <<<"$ms"
      pass "metastore in $region: $ms_name ($ms_id), owner $ms_owner"
      if [[ "$CHECK_METASTORE_STACK" == true && "$ms_name" != "$mname" ]]; then
        warn "$region already has metastore $ms_name; creating $mname will fail (one per region)"
        hint "reuse it (skip the metastore stack) or delete it if unused; see DEPLOYMENT.md step 3.4"
      fi
      if [[ -n "${DATABRICKS_METASTORE_ID:-}" && "$DATABRICKS_METASTORE_ID" != "$ms_id" ]]; then
        fail "DATABRICKS_METASTORE_ID ($DATABRICKS_METASTORE_ID) doesn't match the $region metastore ($ms_id)"
      fi
      [[ "$ms_owner" == "$ADMIN_GROUP" ]] || warn "metastore owner is $ms_owner; the deployment SP must be a metastore admin to create catalogs and external locations"
    fi
  fi
fi

echo
if (( FAILS > 0 )); then
  printf '\033[31mResult: %d failed, %d warnings\033[0m\n' "$FAILS" "$WARNS"; exit 1
fi
printf '\033[32mResult: all checks passed (%d warnings)\033[0m\n' "$WARNS"
