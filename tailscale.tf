resource "helm_release" "tailscale" {
  count = var.tailscale_enabled ? 1 : 0

  name      = "tailscale-operator"
  namespace = "tailscale"

  repository       = var.tailscale_helm_repository
  chart            = var.tailscale_helm_chart
  version          = var.tailscale_helm_version
  create_namespace = true

  set = [
    {
      name  = "oauth.clientId"
      value = var.tailscale_oauth_client_id
    },
    {
      name  = "oauth.clientSecret"
      value = var.tailscale_oauth_client_secret
    }
  ]

  values = [
    yamlencode({
      operatorConfig = {
        nodeSelector = { "node-role.kubernetes.io/control-plane" : "" }
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            effect   = "NoSchedule"
            operator = "Exists"
          }
        ]
      }
      # proxyConfig = {
      #   defaultProxyClass = "hcloud"
      # }
    }),
    yamlencode(var.tailscale_helm_values)
  ]
}
