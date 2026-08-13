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

variable "cluster_name" {
  description = "OKE cluster and network resource name prefix."
  type        = string
  default     = "localshops-production"
}

variable "environment" {
  description = "Environment tag applied to all managed resources."
  type        = string
  default     = "production"
}

variable "vcn_ocid" {
  description = "Existing VCN shared with the Always Free load balancer and DRG."
  type        = string
}

variable "existing_public_subnet_ocid" {
  description = "Existing public subnet used by the preserved Always Free load balancer."
  type        = string
}

variable "existing_public_subnet_cidr" {
  description = "CIDR of the existing load balancer subnet, allowed to reach OKE NodePorts."
  type        = string
  default     = "10.0.0.0/24"
}

variable "control_plane_subnet_cidr" {
  description = "Dedicated private OKE control-plane endpoint subnet."
  type        = string
  default     = "10.0.10.0/24"
}

variable "worker_subnet_cidr" {
  description = "Dedicated private OKE worker subnet."
  type        = string
  default     = "10.0.30.0/24"
}

variable "pod_subnet_cidr" {
  description = "Dedicated private VCN-native pod subnet."
  type        = string
  default     = "10.0.64.0/18"
}

variable "management_cidrs" {
  description = "Dedicated management networks allowed to access the private Kubernetes API. Keep this aligned with bastion_subnet_cidr."
  type        = list(string)
  default     = ["10.0.31.0/29"]
}

variable "bastion_subnet_cidr" {
  description = "Dedicated private subnet used only by the OCI-managed Bastion endpoint."
  type        = string
  default     = "10.0.31.0/29"

  validation {
    condition     = can(cidrhost(var.bastion_subnet_cidr, 0))
    error_message = "bastion_subnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "bastion_client_cidrs" {
  description = "Public source CIDRs permitted to create SSH connections to Bastion. Production uses node02's fixed /32 only."
  type        = list(string)

  validation {
    condition = alltrue([
      for cidr in var.bastion_client_cidrs : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"
    ])
    error_message = "Every Bastion client must be a valid, restricted CIDR; 0.0.0.0/0 is forbidden."
  }
}

variable "freeform_tags" {
  description = "Additional tags merged onto LocalShops resources."
  type        = map(string)
  default     = {}
}
