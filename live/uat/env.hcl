locals {
  config = yamldecode(file("${get_terragrunt_dir()}/config.yaml"))
}

# Supplied as environment variables (GitHub environment secrets in CI).
inputs = {
  subscription_id       = get_env("ARM_SUBSCRIPTION_ID")
  databricks_account_id = get_env("DATABRICKS_ACCOUNT_ID")
}
