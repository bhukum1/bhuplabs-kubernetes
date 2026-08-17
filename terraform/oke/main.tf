locals {
  common_tags = merge(
    {
      managed-by  = "terraform"
      project     = "localshops"
      environment = var.environment
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

  cluster_name             = var.cluster_name
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

  # Reuse the tenancy VCN so the existing Always Free load balancer and the
  # cross-tenancy DRG path to node02 remain usable during and after migration.
  create_vcn                  = false
  vcn_id                      = var.vcn_ocid
  vcn_create_nat_gateway      = "never"
  vcn_create_service_gateway  = "never"
  vcn_create_internet_gateway = "never"
  nat_gateway_id              = oci_core_nat_gateway.oke.id
  nat_route_table_id          = oci_core_route_table.oke_private.id

  subnets = {
    bastion  = { create = "never" }
    operator = { create = "never" }
    cp       = { create = "always", cidr = var.control_plane_subnet_cidr }
    int_lb   = { create = "never" }
    pub_lb   = { create = "never", id = var.existing_public_subnet_ocid }
    workers  = { create = "always", cidr = var.worker_subnet_cidr }
    pods     = { create = "always", cidr = var.pod_subnet_cidr }
  }

  # Interactive API access enters through the dedicated managed Bastion
  # subnet. Worker and pod access is handled by their NSG-to-NSG rules.
  control_plane_allowed_cidrs = var.management_cidrs

  # The public load balancer must be attached to module.oke.pub_lb_nsg_id.
  # These are the only internet-facing ports permitted by that NSG.
  allow_rules_public_lb = {
    public_http = {
      protocol    = 6
      port        = 80
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
    }
    public_https = {
      protocol    = 6
      port        = 443
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
    }
  }

  # The existing load balancer is not attached to the module-created public
  # LB NSG, so explicitly permit NodePort health checks and traffic from its
  # existing subnet only.
  allow_rules_workers = {
    existing_load_balancer_nodeports = {
      protocol    = 6
      port_min    = 30000
      port_max    = 32767
      source      = var.existing_public_subnet_cidr
      source_type = "CIDR_BLOCK"
    }
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
