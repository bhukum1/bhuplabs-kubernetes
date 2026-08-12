variable "tenancy_ocid" {
  description = "Primary OCI tenancy OCID. OCI Resource Manager populates this automatically."
  type        = string
}

variable "compartment_ocid" {
  description = "Dedicated compartment OCID for the LocalShops pilot."
  type        = string
}

variable "region" {
  description = "OCI home region in which the Always Free OKE resources will run."
  type        = string
}

variable "home_region" {
  description = "Primary tenancy home region. Identity resources are created here."
  type        = string
}

variable "kubernetes_version" {
  description = "OKE Kubernetes version currently offered in the selected region, including the v prefix."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Use an OKE version such as v1.34.2."
  }
}

variable "ssh_public_key" {
  description = "Public SSH key installed on workers for emergency node access. Never supply a private key."
  type        = string
}

variable "vcn_cidr" {
  description = "Non-overlapping CIDR for the OKE VCN."
  type        = string
  default     = "10.42.0.0/16"
}

variable "freeform_tags" {
  description = "Additional tags merged onto LocalShops resources."
  type        = map(string)
  default     = {}
}
