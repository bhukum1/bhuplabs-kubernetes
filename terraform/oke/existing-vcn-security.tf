# The OKE module cannot lock down a default security list when it is consuming
# an existing VCN. Manage that inherited list explicitly so old broad rules do
# not remain effective on the OKE and preserved public load-balancer subnets.
data "oci_core_vcn" "existing" {
  vcn_id = var.vcn_ocid
}

resource "oci_core_default_security_list" "existing_vcn" {
  manage_default_resource_id = data.oci_core_vcn.existing.default_security_list_id

  ingress_security_rules {
    description = "Public HTTP for the preserved DUKLY load balancer"
    protocol    = "6"
    source      = "0.0.0.0/0"
    stateless   = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    description = "Public HTTPS for the preserved DUKLY load balancer"
    protocol    = "6"
    source      = "0.0.0.0/0"
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  egress_security_rules {
    description = "Permit egress; component NSGs and Kubernetes policies restrict workloads"
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }
}
