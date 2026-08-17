output "cluster_id" {
  description = "OKE cluster OCID."
  value       = module.oke.cluster_id
}

output "cluster_endpoints" {
  description = "Private OKE API endpoints."
  value       = module.oke.cluster_endpoints
}

output "vcn_id" {
  description = "OKE VCN OCID."
  value       = module.oke.vcn_id
}

output "worker_pool_ids" {
  description = "Managed node-pool OCIDs."
  value       = module.oke.worker_pool_ids
}

output "kubeconfig" {
  description = "Generated kubeconfig. Treat this output as a credential."
  value       = module.oke.cluster_kubeconfig
  sensitive   = true
}

output "bastion_id" {
  description = "OCI-managed Bastion OCID used for temporary OKE API sessions."
  value       = oci_bastion_bastion.oke.id
}

output "bastion_private_endpoint" {
  description = "Private VCN address allocated to the managed Bastion endpoint."
  value       = oci_bastion_bastion.oke.private_endpoint_ip_address
}

output "public_load_balancer_nsg_id" {
  description = "NSG that must be attached to the preserved public load balancer."
  value       = module.oke.pub_lb_nsg_id
}
