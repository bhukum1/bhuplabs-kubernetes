data "oci_core_services" "oracle_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# OCI does not charge an hourly fee for these VCN gateways. They allow private
# OKE workers to reach public dependencies and OCI services without public IPs.
resource "oci_core_nat_gateway" "oke" {
  block_traffic  = false
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-nat"
  vcn_id         = var.vcn_ocid
  freeform_tags  = local.common_tags
}

resource "oci_core_service_gateway" "oke" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-services"
  vcn_id         = var.vcn_ocid
  freeform_tags  = local.common_tags

  services {
    service_id = data.oci_core_services.oracle_services.services[0].id
  }
}

resource "oci_core_route_table" "oke_private" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-private"
  vcn_id         = var.vcn_ocid
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.oke.id
  }

  route_rules {
    destination       = data.oci_core_services.oracle_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.oke.id
  }
}
