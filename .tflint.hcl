# Run "tflint --init" once to download the plugins named here. ci-checks does
# this automatically; it is cheap and idempotent after the first run.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# envs/* declare variables that only some environments consume; dev has no edge
# or proxy tiers, for example. That is deliberate, so the shared variables file
# stays identical across environments.
rule "terraform_unused_declarations" {
  enabled = false
}
