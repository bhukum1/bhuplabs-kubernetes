# OCI Bastion is a managed, zero-cost access path to the private OKE API. The
# dedicated subnet has no public VNICs and can reach only OCI services and the
# control-plane endpoint on TCP/6443.
resource "oci_core_security_list" "oke_bastion" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-bastion"
  vcn_id         = var.vcn_ocid
  freeform_tags  = local.common_tags

  egress_security_rules {
    description      = "Allow Bastion sessions to the private OKE API"
    destination      = var.control_plane_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    stateless        = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    description      = "Allow the managed Bastion endpoint to reach OCI services"
    destination      = data.oci_core_services.oracle_services.services[0].cidr_block
    destination_type = "SERVICE_CIDR_BLOCK"
    protocol         = "6"
    stateless        = false

    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "oke_bastion" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = var.vcn_ocid
  cidr_block                 = var.bastion_subnet_cidr
  display_name               = "${var.cluster_name}-bastion"
  dns_label                  = "okebastion"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.oke_private.id
  security_list_ids          = [oci_core_security_list.oke_bastion.id]
  freeform_tags              = local.common_tags
}

resource "oci_bastion_bastion" "oke" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = oci_core_subnet.oke_bastion.id
  client_cidr_block_allow_list = var.bastion_client_cidrs
  max_session_ttl_in_seconds   = 10800
  name                         = "${var.cluster_name}-admin"
  freeform_tags                = local.common_tags
}

# Managed Bastion private endpoints cannot be attached to an NSG. Limit the
# control-plane ingress to the dedicated /29 subnet instead.
resource "oci_core_network_security_group_security_rule" "bastion_to_apiserver" {
  network_security_group_id = module.oke.control_plane_nsg_id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.bastion_subnet_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "Allow managed OCI Bastion to the private OKE API"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}
