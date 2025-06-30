output "kubeconfig_data" {
  description = "Kubernetes configuration data for connecting to the cluster."
  value       = module.k8s.kubeconfig_data
  sensitive   = true
}

output "ingress_service_load_balancer_public_ipv4" {
  description = "Public IPv4 address of the main ingress load balancer"
  value       = module.k8s.ingress_service_load_balancer_public_ipv4
}

output "ingress_service_load_balancer_public_ipv6" {
  description = "Public IPv6 address of the main ingress load balancer"
  value       = module.k8s.ingress_service_load_balancer_public_ipv6
}

output "argo_workflows_managed_namespaces" {
  description = "List of namespaces where workflows will be managed by Argo Workflows."
  value       = var.argo_workflows_managed_namespaces
}

output "tailscale_urls" {
  description = "Map of URLs to tailscale exposed services."
  value       = local.tailscale_urls
}
