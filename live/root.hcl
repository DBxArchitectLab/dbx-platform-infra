remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.generated.tf"
    if_exists = "overwrite"
  }

  config = {
    resource_group_name  = "rg-dbx-architect-lab"
    storage_account_name = "adlsdbxarchitectlab"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    subscription_id      = get_env("ARM_SUBSCRIPTION_ID")
    use_azuread_auth     = true
  }
  
}

generate "providers" {
  path      = "providers.generated.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "azurerm" {
  subscription_id = var.subscription_id
  resource_provider_registrations = "none"
  features {}
}

provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
}
EOF
}