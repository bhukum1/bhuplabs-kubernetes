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
