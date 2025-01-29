// https://github.com/terraform-linters/tflint/blob/master/docs/guides/config.md
config {
  force = false
}

rule "terraform_required_providers" {
  enabled = false
}
