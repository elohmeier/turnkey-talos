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

output "kanidm_url" {
  description = "URL to access Kanidm identity management system."
  value       = var.kanidm_enabled ? (var.tailscale_enabled ? "https://${local.kanidm_tailscale_hostname}.${var.tailscale_tailnet}" : "https://${local.kanidm_domain}") : null
}

output "pushgateway_url" {
  description = "URL for Prometheus Push Gateway (internal cluster URL)."
  value       = local.pushgateway_enabled ? "http://prometheus-pushgateway.pushgateway.svc.cluster.local:9091" : null
}

output "pushgateway_tailscale_url" {
  description = "Tailscale URL for Prometheus Push Gateway web interface."
  value       = local.pushgateway_tailscale_ingress_enabled ? "https://${local.pushgateway_tailscale_hostname}.${var.tailscale_tailnet}" : null
}
