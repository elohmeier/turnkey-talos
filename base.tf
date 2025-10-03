# Auto-create S3 buckets for backups
resource "minio_s3_bucket" "talos_backup" {
  bucket         = "${var.cluster_name}-talos-backup"
  acl            = "private"
  object_locking = false
}

resource "minio_ilm_policy" "talos_backup" {
  bucket = minio_s3_bucket.talos_backup.bucket
  rule {
    id         = "expire-7d"
    status     = "Enabled"
    expiration = "7d"
  }
}

resource "minio_s3_bucket" "longhorn_backup" {
  bucket         = "${var.cluster_name}-longhorn-backup"
  acl            = "private"
  object_locking = false
}

module "k8s" {
  # source  = "hcloud-k8s/kubernetes/hcloud"
  # version = "1.5.0"

  # source = "git::https://github.com/elohmeier/terraform-hcloud-kubernetes.git?ref=main"
  source = "git::/Users/enno/repos/github.com/hcloud-k8s/terraform-hcloud-kubernetes?ref=main"
  # source = "/Users/enno/repos/github.com/hcloud-k8s/terraform-hcloud-kubernetes"

  talos_backup_version = "v0.1.0-beta.3"

  cluster_name              = var.cluster_name
  cluster_delete_protection = var.cluster_delete_protection
  hcloud_token              = var.hcloud_token

  control_plane_nodepools = [
    { name = "control", type = var.control_plane_type, location = var.location, count = var.control_plane_count }
  ]
  worker_nodepools = [
    { name = "worker", type = var.worker_type, location = var.location, count = var.worker_count },
  ]

  cluster_autoscaler_nodepools = var.cluster_autoscaler_nodepools

  cluster_autoscaler_helm_values = {
    extraArgs = {
      enforce-node-group-min-size   = true
      scale-down-delay-after-add    = "45m"
      scale-down-delay-after-delete = "4m"
      scale-down-unneeded-time      = "5m"
    }
  }

  # Export configs for Talos and Kube API access
  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  # Storage
  hcloud_csi_enabled             = false
  longhorn_enabled               = true
  longhorn_default_storage_class = true
  longhorn_helm_values = {
    metrics = {
      serviceMonitor = {
        enabled = true
      }
    }
    defaultBackupStore = {
      backupTarget                 = "s3://${var.cluster_name}-longhorn-backup@${var.location}/"
      backupTargetCredentialSecret = "longhorn-backup-secret"
      pollInterval                 = 300
    }
    defaultSettings = {
      # Storage optimization settings
      storageOverProvisioningPercentage = 90 # Reduce from 100% to prevent over-allocation
      storageMinimalAvailablePercentage = 20 # Reduce from 25% to allow more usable space

      # Automatic cleanup settings
      autoCleanupSystemGeneratedSnapshot              = true
      autoCleanupRecurringJobBackupSnapshot           = true
      autoCleanupSnapshotWhenDeleteBackup             = true
      autoCleanupSnapshotAfterOnDemandBackupCompleted = true

      # Orphan resource management
      orphanResourceAutoDeletion            = true
      orphanResourceAutoDeletionGracePeriod = 300

      # Snapshot management
      snapshotMaxCount = 50 # Reduce from 250 to limit snapshot proliferation

      # Replica optimization
      defaultReplicaCount     = 2             # Reduce from 3 for non-critical workloads
      replicaSoftAntiAffinity = true          # Better distribution with softer constraints
      replicaAutoBalance      = "best-effort" # Automatically rebalance replicas

      # Performance settings
      guaranteedInstanceManagerCPU = 10 # Reserve minimal CPU (10m) for better density
    }
  }

  # Cilium monitoring
  cilium_service_monitor_enabled = true
  cilium_hubble_enabled          = true
  cilium_hubble_relay_enabled    = true
  cilium_hubble_ui_enabled       = true
  cilium_helm_values = {
    hubble = {
      metrics = {
        enabled = [
          "dns:query;ignoreAAAA",
          "drop",
          "tcp",
          "flow",
          "icmp",
          "http"
        ]
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
        dashboards = {
          enabled   = true
          label     = "grafana_dashboard"
          namespace = "kube-system"
        }
      }
      relay = {
        prometheus = {
          enabled = true
          serviceMonitor = {
            enabled  = true
            interval = "15s"
          }
        }
      }
      ui = {
        ingress = var.tailscale_enabled ? {
          enabled   = true
          className = "tailscale"
          hosts     = ["${var.cluster_name}-hubble.${var.tailscale_tailnet}"]
          tls = [{
            hosts = ["${var.cluster_name}-hubble.${var.tailscale_tailnet}"]
          }]
        } : null
      }
    }
    envoy = {
      prometheus = {
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
      }
      dashboards = {
        enabled   = true
        label     = "grafana_dashboard"
        namespace = "kube-system"
      }
    }
    operator = {
      prometheus = {
        enabled = true
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
      }
      dashboards = {
        enabled   = true
        label     = "grafana_dashboard"
        namespace = "kube-system"
      }
    }
    dashboards = {
      enabled   = true
      label     = "grafana_dashboard"
      namespace = "kube-system"
    }
  }

  # Extras
  cert_manager_enabled  = true
  ingress_nginx_enabled = true

  # Disable Talos CoreDNS when using custom CoreDNS, enable it otherwise
  talos_coredns_enabled = !var.custom_coredns_enabled

  # Set kubelet cluster DNS to match our custom CoreDNS service IP when enabled
  # Dynamically calculated as the 10th IP in the service subnet
  kubernetes_kubelet_cluster_dns = var.custom_coredns_enabled ? [cidrhost(var.network_service_ipv4_cidr, 10)] : null

  # Enable NGINX metrics for Prometheus monitoring
  ingress_nginx_helm_values = {
    controller = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = var.victoriametrics_enabled
          additionalLabels = {
            "prometheus.io/operator" = "victoriametrics"
          }
        }
      }
      allowSnippetAnnotations = true
      config = {
        annotations-risk-level = "Critical"
      }
    }
  }

  talos_extra_remote_manifests = [
    "https://github.com/grafana/grafana-operator/releases/download/${var.grafana_operator_helm_version}/crds.yaml",
    "https://github.com/k8up-io/k8up/releases/download/k8up-${var.k8up_helm_version}/k8up-crd.yaml"
  ]

  # VictoriaLogs
  talos_extra_kernel_args    = ["talos.logging.kernel=udp://127.0.0.1:6050"]
  talos_logging_destinations = [{ endpoint = "udp://127.0.0.1:6051", format = "json_lines" }]

  talos_backup_s3_endpoint   = "https://${var.location}.your-objectstorage.com"
  talos_backup_s3_region     = var.location
  talos_backup_s3_bucket     = "${var.cluster_name}-talos-backup"
  talos_backup_s3_access_key = var.s3_admin_access_key
  talos_backup_s3_secret_key = var.s3_admin_secret_key
}
