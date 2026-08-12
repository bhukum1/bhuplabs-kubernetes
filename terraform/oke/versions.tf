terraform {
  # OCI Resource Manager currently executes Terraform 1.5.7. Keep this
  # configuration compatible with it while allowing newer local CLIs to run
  # format and validation checks.
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.30.0, < 9.0.0"
    }
  }
}

provider "oci" {
  region = var.region
}

provider "oci" {
  alias  = "home"
  region = var.home_region
}
