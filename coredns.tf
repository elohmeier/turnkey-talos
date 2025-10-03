locals {
  coredns_namespace = "kube-system"

  # Calculate CoreDNS service IP dynamically from the service CIDR
  # Use the 10th IP in the service subnet (following Kubernetes convention)
  coredns_service_ip = cidrhost(var.network_service_ipv4_cidr, 10)

  # Tailscale nameserver service IP
  # Use a high IP in the service subnet to avoid conflicts (253rd IP)
  tailscale_nameserver_ip = cidrhost(var.network_service_ipv4_cidr, 253)

  # CoreDNS server configuration
  # We only need to override when adding Tailscale DNS forwarding
  coredns_servers = var.tailscale_enabled ? [{
    zones = [{ zone = "." }]
    port  = 53
    plugins = [
      { name = "errors" },
      {
        name        = "health"
        configBlock = "lameduck 5s"
      },
      { name = "ready" },
      {
        name        = "log"
        parameters  = "."
        configBlock = "class error"
      },
      {
        name       = "prometheus"
        parameters = ":9153"
      },
      {
        name        = "kubernetes"
        parameters  = "cluster.local in-addr.arpa ip6.arpa"
        configBlock = <<-EOT
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
        EOT
      },
      # Forward .ts.net queries to Tailscale nameserver
      # Using our custom service with static IP (see tailscale.tf)
      {
        name       = "forward"
        parameters = "ts.net ${local.tailscale_nameserver_ip}"
      },
      {
        name        = "forward"
        parameters  = ". /etc/resolv.conf"
        configBlock = "max_concurrent 1000"
      },
      {
        name        = "cache"
        parameters  = "30"
        configBlock = <<-EOT
          disable success cluster.local
          disable denial cluster.local
        EOT
      },
      { name = "loop" },
      { name = "reload" },
      { name = "loadbalance" }
    ]
  }] : null

  # Custom zone files for additional DNS zones
  coredns_zone_files = {
    # Example: "example.com.zone" = "example.com IN SOA ns1.example.com. admin.example.com. ..."
  }
}

# CoreDNS Helm release
# This configuration replaces the default Talos CoreDNS with a custom deployment.
# Requirements configured in base.tf:
# - talos_coredns_enabled = false (disables Talos CoreDNS)
# - kubernetes_kubelet_cluster_dns dynamically set to the 10th IP in service subnet
resource "helm_release" "coredns" {
  count = var.custom_coredns_enabled ? 1 : 0

  name      = "coredns"
  namespace = local.coredns_namespace

  repository       = "https://coredns.github.io/helm"
  chart            = "coredns"
  version          = "1.44.3"
  create_namespace = false
  wait             = false
  replace          = true

  values = [
    yamlencode(merge(
      {
        # Scale based on cluster size
        replicaCount = var.control_plane_count > 1 ? 2 : 1

        # Override k8s-app label for network policy compatibility
        k8sAppLabelOverride = "kube-dns"

        # Service configuration - required for custom cluster DNS
        service = {
          name       = "kube-dns"
          clusterIP  = local.coredns_service_ip
          clusterIPs = [local.coredns_service_ip]
        }

        # Deployment configuration
        deployment = {
          annotations = {
            "reloader.stakater.com/auto" = "true"
          }
        }

        # Pod disruption budget for HA
        podDisruptionBudget = {
          enabled = var.control_plane_count > 1
        }

        # Prometheus monitoring
        prometheus = {
          monitor = {
            enabled = var.victoriametrics_enabled
            additionalLabels = {
              "monitoring.coreos.com/prometheus" = "kube-prometheus"
            }
          }
        }

        # Node placement for clusters without workers
        nodeSelector = var.worker_count == 0 ? {
          "node-role.kubernetes.io/control-plane" = ""
        } : {}

        tolerations = var.worker_count == 0 ? [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ] : []

        # Affinity for spreading across nodes
        affinity = var.control_plane_count > 1 ? {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/instance" = "coredns"
                      "app.kubernetes.io/name"     = "coredns"
                    }
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        } : {}
      },
      # Add custom server configuration when Tailscale is enabled
      var.tailscale_enabled ? {
        servers = local.coredns_servers
      } : {}
    ))
  ]
}
