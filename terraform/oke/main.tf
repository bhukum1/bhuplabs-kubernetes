locals {
  common_tags = merge(
    {
      managed-by  = "terraform"
      project     = "localshops"
      environment = "pilot"
      cost-policy = "always-free-only"
    },
    var.freeform_tags,
  )
}

module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.4.3"

  providers = {
    oci      = oci
    oci.home = oci.home
  }

  tenancy_id     = var.tenancy_ocid
  compartment_id = var.compartment_ocid
  region         = var.region
  home_region    = var.home_region

  cluster_name             = "localshops-pilot"
  cluster_type             = "basic"
  kubernetes_version       = var.kubernetes_version
  control_plane_is_public  = false
  create_bastion           = false
  create_operator          = false
  create_cluster           = true
  create_iam_resources     = true
  cni_type                 = "npn"
  max_pods_per_node        = 31
  load_balancers           = "public"
  preferred_load_balancer  = "public"
  lockdown_default_seclist = true

  create_vcn                  = true
  vcn_name                    = "localshops-pilot"
  vcn_dns_label               = "localshops"
  vcn_cidrs                   = [var.vcn_cidr]
  vcn_create_nat_gateway      = "always"
  vcn_create_service_gateway  = "always"
  vcn_create_internet_gateway = "always"

  subnets = {
    bastion  = { create = "never" }
    operator = { create = "never" }
    cp       = { create = "always", newbits = 8, netnum = 10 }
    int_lb   = { create = "never" }
    pub_lb   = { create = "always", newbits = 8, netnum = 20 }
    workers  = { create = "always", newbits = 8, netnum = 30 }
    pods     = { create = "always", newbits = 4, netnum = 4 }
  }

  # Hard cost boundary: two Always Free Ampere nodes and no fallback pool.
  worker_pool_mode = "node-pool"
  worker_pool_size = 2
  worker_pools = {
    application = {}
  }
  worker_shape = {
    shape            = "VM.Standard.A1.Flex"
    ocpus            = 1
    memory           = 6
    boot_volume_size = 50
  }
  worker_is_public                      = false
  worker_legacy_imds_endpoints_disabled = true
  worker_pv_transit_encryption          = true
  ssh_public_key                        = var.ssh_public_key

  output_detail = false
  timezone      = "Asia/Kolkata"
  freeform_tags = {
    cluster           = local.common_tags
    iam               = local.common_tags
    network           = local.common_tags
    service_lb        = local.common_tags
    workers           = local.common_tags
    persistent_volume = local.common_tags
  }
}
