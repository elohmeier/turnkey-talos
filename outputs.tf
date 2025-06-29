output "kubeconfig_data" {
  description = "Kubernetes configuration data for connecting to the cluster."
  value       = module.k8s.kubeconfig_data
  sensitive   = true
}

output "argo_workflows_managed_namespaces" {
  description = "List of namespaces where workflows will be managed by Argo Workflows."
  value       = var.argo_workflows_managed_namespaces
}

output "tailscale_urls" {
  description = "Map of URLs to tailscale exposed services."
  value       = local.tailscale_urls
}
