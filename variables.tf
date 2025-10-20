variable "cluster_name" {
  type        = string
  description = "Specifies the name of the cluster. This name is used to identify the cluster within the infrastructure and should be unique across all deployments."

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster name must start and end with a lowercase letter or number, can contain hyphens, and must be no longer than 32 characters."
  }
}

variable "cluster_delete_protection" {
  type        = bool
  default     = true
  description = "Adds delete protection for resources that support it."
}

variable "hcloud_token" {
  type        = string
  description = "The Hetzner Cloud API token used for authentication with Hetzner Cloud services. This token should be treated as sensitive information."
  sensitive   = true
}

variable "control_plane_count" {
  type        = number
  default     = 3
  description = "Number of control plane nodes to deploy."

  validation {
    condition     = var.control_plane_count > 0 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be a positive odd number for proper etcd quorum."
  }
}

variable "worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes to deploy."

  validation {
    condition     = var.worker_count >= 0
    error_message = "Worker count must be zero or greater."
  }
}

variable "control_plane_type" {
  type        = string
  default     = "ccx13"
  description = "The Hetzner Cloud server type for control plane nodes. Examples: ccx13, cpx11, cx22, etc."
}

variable "worker_type" {
  type        = string
  default     = "ccx23"
  description = "The Hetzner Cloud server type for worker nodes. Examples: ccx23, cpx21, cx32, etc."
}

variable "cluster_autoscaler_nodepools" {
  type = list(object({
    name        = string
    location    = string
    type        = string
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    taints      = optional(list(string), [])
    min         = optional(number, 0)
    max         = number
  }))
  default     = []
  description = "Defines configuration settings for Autoscaler node pools within the cluster."

  validation {
    condition     = length(var.cluster_autoscaler_nodepools) == length(distinct([for np in var.cluster_autoscaler_nodepools : np.name]))
    error_message = "Autoscaler nodepool names must be unique to avoid configuration conflicts."
  }

  validation {
    condition = alltrue([
      for np in var.cluster_autoscaler_nodepools : np.max >= coalesce(np.min, 0)
    ])
    error_message = "Max size of a nodepool must be greater than or equal to its Min size."
  }

  validation {
    condition = alltrue([
      for np in var.cluster_autoscaler_nodepools : contains([
        "fsn1", "nbg1", "hel1", "ash", "hil", "sin"
      ], np.location)
    ])
    error_message = "Each nodepool location must be one of: 'fsn1' (Falkenstein), 'nbg1' (Nuremberg), 'hel1' (Helsinki), 'ash' (Ashburn), 'hil' (Hillsboro), 'sin' (Singapore)."
  }

  validation {
    condition = alltrue([
      for np in var.cluster_autoscaler_nodepools : length(var.cluster_name) + length(np.name) <= 56
    ])
    error_message = "The combined length of the cluster name and any Cluster Autoscaler nodepool name must not exceed 56 characters."
  }
}

variable "s3_admin_access_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "S3 Admin Access Key for managing S3 resources (buckets, access keys, etc.)."
}

variable "s3_admin_secret_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "S3 Admin Secret Access Key for managing S3 resources (buckets, access keys, etc.)."
}


# Kubetail
variable "kubetail_helm_repository" {
  type        = string
  default     = "https://kubetail-org.github.io/helm-charts/"
  description = "URL of the Helm repository where the Kubetail chart is located."
}

variable "kubetail_helm_chart" {
  type        = string
  default     = "kubetail"
  description = "Name of the Helm chart used for deploying Kubetail."
}

variable "kubetail_helm_version" {
  type        = string
  default     = "0.15.2"
  description = "Version of the Kubetail Helm chart to deploy."
}

variable "kubetail_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Kubetail chart deployment. These values will merge with and will override the default values provided by the Kubetail Helm chart."
}

variable "kubetail_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of Kubetail for real-time log viewing."
}

variable "kubetail_allowed_namespaces" {
  type        = list(string)
  default     = []
  description = "List of namespaces that Kubetail is allowed to access. If empty, all namespaces are accessible."
}

# CloudNative-PG
variable "cloudnative_pg_helm_repository" {
  type        = string
  default     = "https://cloudnative-pg.github.io/charts"
  description = "URL of the Helm repository where the CloudNative-PG chart is located."
}

variable "cloudnative_pg_helm_chart" {
  type        = string
  default     = "cloudnative-pg"
  description = "Name of the Helm chart used for deploying CloudNative-PG."
}

variable "cloudnative_pg_helm_version" {
  type        = string
  default     = "0.26.0"
  description = "Version of the CloudNative-PG Helm chart to deploy."
}

variable "cloudnative_pg_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the CloudNative-PG chart deployment. These values will merge with and will override the default values provided by the CloudNative-PG Helm chart."
}

variable "cloudnative_pg_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of CloudNative-PG operator for PostgreSQL management."
}


# CloudNative-PG Cluster Chart
variable "cloudnative_pg_cluster_helm_repository" {
  type        = string
  default     = "https://cloudnative-pg.github.io/charts"
  description = "URL of the Helm repository where the CloudNative-PG cluster chart is located."
}

variable "cloudnative_pg_cluster_helm_chart" {
  type        = string
  default     = "cluster"
  description = "Name of the Helm chart used for deploying CloudNative-PG clusters."
}

variable "cloudnative_pg_cluster_helm_version" {
  type        = string
  default     = "0.3.1"
  description = "Version of the CloudNative-PG cluster Helm chart to deploy."
}

variable "cloudnative_pg_cluster_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the CloudNative-PG cluster chart deployment. These values will merge with and will override the default values provided by the CloudNative-PG cluster Helm chart."
}

# CloudNative-PG Grafana Dashboard
variable "cloudnative_pg_grafana_dashboard_helm_repository" {
  type        = string
  default     = "https://cloudnative-pg.github.io/grafana-dashboards"
  description = "URL of the Helm repository where the CloudNative-PG Grafana dashboard chart is located."
}

variable "cloudnative_pg_grafana_dashboard_helm_chart" {
  type        = string
  default     = "cluster"
  description = "Name of the Helm chart used for deploying CloudNative-PG Grafana dashboard."
}

variable "cloudnative_pg_grafana_dashboard_helm_version" {
  type        = string
  default     = "0.0.5"
  description = "Version of the CloudNative-PG Grafana dashboard Helm chart to deploy."
}

variable "cloudnative_pg_grafana_dashboard_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the CloudNative-PG Grafana dashboard chart deployment. These values will merge with and will override the default values provided by the CloudNative-PG Grafana dashboard Helm chart."
}



# Tailscale
variable "tailscale_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of Tailscale Kubernetes Operator for secure networking and access control."
}

variable "tailscale_helm_repository" {
  type        = string
  default     = "https://pkgs.tailscale.com/helmcharts"
  description = "URL of the Helm repository where the Tailscale Operator chart is located."
}

variable "tailscale_helm_chart" {
  type        = string
  default     = "tailscale-operator"
  description = "Name of the Helm chart used for deploying Tailscale Operator."
}

variable "tailscale_helm_version" {
  type        = string
  default     = "1.88.3"
  description = "Version of the Tailscale Operator Helm chart to deploy."
}

variable "tailscale_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Tailscale Operator chart deployment. These values will merge with and will override the default values provided by the Tailscale Operator Helm chart."
}

variable "tailscale_oauth_client_id" {
  type        = string
  default     = ""
  description = "OAuth client ID for Tailscale Kubernetes Operator. Required when tailscale_enabled is true. Create this in the Tailscale admin console under OAuth clients with 'Devices Core' and 'Auth Keys' write scopes."
  sensitive   = true

  validation {
    condition     = !var.tailscale_enabled || var.tailscale_oauth_client_id != ""
    error_message = "tailscale_oauth_client_id must be provided when tailscale_enabled is true."
  }
}

variable "tailscale_oauth_client_secret" {
  type        = string
  default     = ""
  description = "OAuth client secret for Tailscale Kubernetes Operator. Required when tailscale_enabled is true. This is the secret corresponding to the OAuth client ID."
  sensitive   = true

  validation {
    condition     = !var.tailscale_enabled || var.tailscale_oauth_client_secret != ""
    error_message = "tailscale_oauth_client_secret must be provided when tailscale_enabled is true."
  }
}

variable "tailscale_tailnet" {
  type        = string
  default     = ""
  description = "Tailnet name for Tailscale ingress configuration. This should be your tailnet's domain name (e.g., 'example.ts.net')."
}

variable "network_service_ipv4_cidr" {
  type        = string
  default     = "10.0.96.0/19"
  description = "The IPv4 CIDR block for Kubernetes services. Default matches the hcloud-k8s module's calculated default when network_ipv4_cidr is 10.0.0.0/16. Override if you customize network_ipv4_cidr in the module."
}

variable "location" {
  type        = string
  default     = "fsn1"
  description = "The Hetzner Cloud location/region where resources will be deployed (e.g., 'fsn1', 'nbg1', 'hel1')."
}

# VictoriaMetrics
variable "victoriametrics_helm_repository" {
  type        = string
  default     = "https://victoriametrics.github.io/helm-charts/"
  description = "URL of the Helm repository where the VictoriaMetrics K8s Stack chart is located."
}

variable "victoriametrics_helm_chart" {
  type        = string
  default     = "victoria-metrics-k8s-stack"
  description = "Name of the Helm chart used for deploying VictoriaMetrics K8s Stack."
}

variable "victoriametrics_helm_version" {
  type        = string
  default     = "0.60.1"
  description = "Version of the VictoriaMetrics K8s Stack Helm chart to deploy."
}

variable "victoriametrics_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the VictoriaMetrics K8s Stack chart deployment. These values will merge with and will override the default values provided by the VictoriaMetrics K8s Stack Helm chart."
}

variable "victoriametrics_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of VictoriaMetrics K8s Stack for metrics collection and monitoring."
}

variable "victoriametrics_grafana_database_enabled" {
  type        = bool
  default     = false
  description = "Enables PostgreSQL database for Grafana in VictoriaMetrics stack using CloudNative-PG. Requires both victoriametrics_enabled and cloudnative_pg_enabled to be true."

  validation {
    condition     = !var.victoriametrics_grafana_database_enabled || (var.victoriametrics_enabled && var.cloudnative_pg_enabled)
    error_message = "victoriametrics_grafana_database_enabled can only be true when both victoriametrics_enabled and cloudnative_pg_enabled are true."
  }
}

variable "victoriametrics_alertmanager_pushover_enabled" {
  type        = bool
  default     = false
  description = "Enables Pushover notifications for VictoriaMetrics Alertmanager. Requires victoriametrics_enabled to be true."

  validation {
    condition     = !var.victoriametrics_alertmanager_pushover_enabled || var.victoriametrics_enabled
    error_message = "victoriametrics_alertmanager_pushover_enabled can only be true when victoriametrics_enabled is also true."
  }
}

variable "victoriametrics_alertmanager_pushover_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Pushover application token for VictoriaMetrics Alertmanager notifications. Required when victoriametrics_alertmanager_pushover_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_pushover_enabled || var.victoriametrics_alertmanager_pushover_token != ""
    error_message = "victoriametrics_alertmanager_pushover_token must be provided when victoriametrics_alertmanager_pushover_enabled is true."
  }
}

variable "victoriametrics_alertmanager_pushover_user_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Pushover user key for VictoriaMetrics Alertmanager notifications. Required when victoriametrics_alertmanager_pushover_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_pushover_enabled || var.victoriametrics_alertmanager_pushover_user_key != ""
    error_message = "victoriametrics_alertmanager_pushover_user_key must be provided when victoriametrics_alertmanager_pushover_enabled is true."
  }
}

variable "victoriametrics_alertmanager_pushover_priority" {
  type        = number
  default     = 0
  description = "Pushover message priority for VictoriaMetrics Alertmanager notifications. Valid values: -2 (lowest), -1 (low), 0 (normal), 1 (high), 2 (emergency)."

  validation {
    condition     = contains([-2, -1, 0, 1, 2], var.victoriametrics_alertmanager_pushover_priority)
    error_message = "victoriametrics_alertmanager_pushover_priority must be one of: -2 (lowest), -1 (low), 0 (normal), 1 (high), 2 (emergency)."
  }
}

variable "victoriametrics_alertmanager_pushover_sound" {
  type        = string
  default     = "pushover"
  description = "Pushover notification sound for VictoriaMetrics Alertmanager notifications. Common values: pushover, bike, bugle, cashregister, classical, cosmic, falling, gamelan, incoming, intermission, magic, mechanical, pianobar, siren, spacealarm, tugboat, alien, climb, persistent, echo, updown, none."
}

variable "victoriametrics_alertmanager_email_enabled" {
  type        = bool
  default     = false
  description = "Enables email notifications for VictoriaMetrics Alertmanager. Requires victoriametrics_enabled to be true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_enabled
    error_message = "victoriametrics_alertmanager_email_enabled can only be true when victoriametrics_enabled is also true."
  }
}

variable "victoriametrics_alertmanager_email_smtp_host" {
  type        = string
  default     = ""
  description = "SMTP server hostname for VictoriaMetrics Alertmanager email notifications. Required when victoriametrics_alertmanager_email_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_alertmanager_email_smtp_host != ""
    error_message = "victoriametrics_alertmanager_email_smtp_host must be provided when victoriametrics_alertmanager_email_enabled is true."
  }
}

variable "victoriametrics_alertmanager_email_smtp_port" {
  type        = number
  default     = 587
  description = "SMTP server port for VictoriaMetrics Alertmanager email notifications. Common values: 25 (unencrypted), 587 (STARTTLS), 465 (SSL/TLS)."

  validation {
    condition     = var.victoriametrics_alertmanager_email_smtp_port > 0 && var.victoriametrics_alertmanager_email_smtp_port <= 65535
    error_message = "victoriametrics_alertmanager_email_smtp_port must be a valid port number between 1 and 65535."
  }
}

variable "victoriametrics_alertmanager_email_smtp_username" {
  type        = string
  default     = ""
  description = "SMTP username for VictoriaMetrics Alertmanager email notifications. Required when victoriametrics_alertmanager_email_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_alertmanager_email_smtp_username != ""
    error_message = "victoriametrics_alertmanager_email_smtp_username must be provided when victoriametrics_alertmanager_email_enabled is true."
  }
}

variable "victoriametrics_alertmanager_email_smtp_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "SMTP password for VictoriaMetrics Alertmanager email notifications. Required when victoriametrics_alertmanager_email_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_alertmanager_email_smtp_password != ""
    error_message = "victoriametrics_alertmanager_email_smtp_password must be provided when victoriametrics_alertmanager_email_enabled is true."
  }
}

variable "victoriametrics_alertmanager_email_from" {
  type        = string
  default     = ""
  description = "From email address for VictoriaMetrics Alertmanager email notifications. Required when victoriametrics_alertmanager_email_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_alertmanager_email_from != ""
    error_message = "victoriametrics_alertmanager_email_from must be provided when victoriametrics_alertmanager_email_enabled is true."
  }
}

variable "victoriametrics_alertmanager_email_to" {
  type        = string
  default     = ""
  description = "Email address for VictoriaMetrics Alertmanager email notifications. Required when victoriametrics_alertmanager_email_enabled is true."

  validation {
    condition     = !var.victoriametrics_alertmanager_email_enabled || var.victoriametrics_alertmanager_email_to != ""
    error_message = "victoriametrics_alertmanager_email_to must contain email address when victoriametrics_alertmanager_email_enabled is true."
  }
}

variable "victoriametrics_alertmanager_email_subject" {
  type        = string
  default     = "[{{ .Status | toUpper }}{{ if eq .Status \"firing\" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.SortedPairs.Values | join \" \" }} {{ if gt (len .CommonLabels) (len .GroupLabels) }}({{ with .CommonLabels.Remove .GroupLabels.Names }}{{ .Values | join \" \" }}{{ end }}){{ end }}"
  description = "Email subject template for VictoriaMetrics Alertmanager email notifications. Supports Go templating."
}

variable "victoriametrics_alertmanager_email_require_tls" {
  type        = bool
  default     = true
  description = "Require TLS for SMTP connection in VictoriaMetrics Alertmanager email notifications."
}


# VictoriaLogs
variable "victorialogs_helm_repository" {
  type        = string
  default     = "https://victoriametrics.github.io/helm-charts/"
  description = "URL of the Helm repository where the VictoriaLogs Single chart is located."
}

variable "victorialogs_helm_chart" {
  type        = string
  default     = "victoria-logs-single"
  description = "Name of the Helm chart used for deploying VictoriaLogs Single."
}

variable "victorialogs_helm_version" {
  type        = string
  default     = "0.11.11"
  description = "Version of the VictoriaLogs Single Helm chart to deploy."
}

variable "victorialogs_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the VictoriaLogs Single chart deployment. These values will merge with and will override the default values provided by the VictoriaLogs Single Helm chart."
}

variable "victorialogs_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of VictoriaLogs Single for logs storage."
}

# Grafana Operator
variable "grafana_operator_helm_repository" {
  type        = string
  default     = "oci://ghcr.io/grafana/helm-charts"
  description = "URL of the Helm repository where the Grafana Operator chart is located."
}

variable "grafana_operator_helm_chart" {
  type        = string
  default     = "grafana-operator"
  description = "Name of the Helm chart used for deploying Grafana Operator."
}

variable "grafana_operator_helm_version" {
  type        = string
  default     = "v5.18.0"
  description = "Version of the Grafana Operator Helm chart to deploy."
}

variable "grafana_operator_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Grafana Operator chart deployment. These values will merge with and will override the default values provided by the Grafana Operator Helm chart."
}

variable "grafana_operator_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of Grafana Operator for managing Grafana instances."
}

variable "grafana_enabled" {
  type        = bool
  default     = true
  description = "Enables the deployment of a Grafana instance using the Grafana Operator. Requires grafana_operator_enabled to be true."

  validation {
    condition     = !var.grafana_enabled || var.grafana_operator_enabled
    error_message = "grafana_enabled can only be true when grafana_operator_enabled is also true."
  }
}

variable "grafana_admin_user" {
  type        = string
  default     = "admin"
  description = "Admin username for the Grafana instance."
}

variable "grafana_admin_password" {
  type        = string
  default     = "admin"
  sensitive   = true
  description = "Admin password for the Grafana instance."
}

# Argo Workflows
variable "argo_workflows_helm_repository" {
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
  description = "URL of the Helm repository where the Argo Workflows chart is located."
}

variable "argo_workflows_helm_chart" {
  type        = string
  default     = "argo-workflows"
  description = "Name of the Helm chart used for deploying Argo Workflows."
}

variable "argo_workflows_helm_version" {
  type        = string
  default     = "0.45.26"
  description = "Version of the Argo Workflows Helm chart to deploy."
}

variable "argo_workflows_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Argo Workflows chart deployment. These values will merge with and will override the default values provided by the Argo Workflows Helm chart."
}

variable "argo_workflows_enabled" {
  type        = bool
  default     = false
  description = "Enables the deployment of Argo Workflows."
}

variable "argo_workflows_managed_namespaces" {
  type        = list(string)
  default     = ["argo-workflows-managed"]
  description = "A list of namespaces where workflows will be managed by Argo Workflows."
}

# Kanidm (via KaniOP)
variable "kanidm_enabled" {
  type        = bool
  default     = false
  description = "Enables the deployment of Kanidm identity management system via KaniOP."
}

variable "kaniop_helm_repository" {
  type        = string
  default     = "oci://ghcr.io/pando85/helm-charts"
  description = "URL of the Helm repository where the KaniOP chart is located."
}

variable "kaniop_helm_chart" {
  type        = string
  default     = "kaniop"
  description = "Name of the Helm chart used for deploying KaniOP."
}

variable "kaniop_helm_version" {
  type        = string
  default     = "0.0.0-alpha.1"
  description = "Version of the KaniOP Helm chart to deploy."
}

variable "kaniop_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the KaniOP chart deployment. These values will merge with and will override the default values provided by the KaniOP Helm chart."
}

variable "kaniop_image_repository" {
  type        = string
  default     = "ghcr.io/pando85/kaniop"
  description = "Docker image repository for KaniOP."
}

variable "kaniop_image_tag" {
  type        = string
  default     = "latest"
  description = "Docker image tag for KaniOP."
}

variable "kanidm_helm_repository" {
  type        = string
  default     = ""
  description = "URL of the Helm repository where the Kanidm chart is located. If empty, expects a local chart path."
}

variable "kanidm_helm_chart" {
  type        = string
  default     = "kanidm"
  description = "Name of the Helm chart used for deploying Kanidm when using a repository. Ignored when repository is empty (uses local chart)."
}

variable "kanidm_helm_version" {
  type        = string
  default     = ""
  description = "Version of the Kanidm Helm chart to deploy. Leave empty for local charts."
}

variable "kanidm_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Kanidm chart deployment. These values will merge with and will override the default values provided by the Kanidm Helm chart."
}

variable "kanidm_domain" {
  type        = string
  default     = ""
  description = "Domain name for Kanidm. If not set, defaults to tailscale hostname when tailscale is enabled, otherwise cluster_name.local."
}

variable "kanidm_replicas" {
  type        = number
  default     = 1
  description = "Number of Kanidm server replicas to deploy."
}

variable "kanidm_image" {
  type        = string
  default     = "kanidm/server:latest"
  description = "Docker image to use for Kanidm server."
}

variable "kanidm_image_pull_policy" {
  type        = string
  default     = "IfNotPresent"
  description = "Image pull policy for Kanidm server."
}

variable "kanidm_storage_size" {
  type        = string
  default     = "1Gi"
  description = "Storage size for Kanidm persistent volume claim."
}

variable "kanidm_cert_issuer" {
  type        = string
  default     = "selfsigned-issuer"
  description = "Certificate issuer name for Kanidm TLS certificates."
}

variable "kanidm_cert_issuer_kind" {
  type        = string
  default     = "Issuer"
  description = "Certificate issuer kind (Issuer or ClusterIssuer)."
}

variable "kanidm_ingress_enabled" {
  type        = bool
  default     = true
  description = "Enable ingress for Kanidm."
}

variable "kanidm_initial_user" {
  type = object({
    enabled     = bool
    name        = string
    displayName = string
    mail        = list(string)
  })
  default = {
    enabled     = false
    name        = ""
    displayName = ""
    mail        = []
  }
  description = "Initial Kanidm user configuration."
}

variable "kanidm_grafana_oauth_enabled" {
  type        = bool
  default     = false
  description = "Enable OAuth2 integration between Grafana and Kanidm."
}

variable "kanidm_oauth2_clients" {
  type = list(object({
    name         = string
    displayName  = string
    origin       = string
    redirectUrls = list(string)
    scopeMap = list(object({
      group  = string
      scopes = list(string)
    }))
    supScopeMap = optional(list(object({
      group  = string
      scopes = list(string)
    })))
    public                         = optional(bool)
    strictRedirectUrl              = optional(bool)
    preferShortUsername            = optional(bool)
    allowLocalhostRedirect         = optional(bool)
    allowInsecureClientDisablePkce = optional(bool)
  }))
  default     = []
  description = "List of OAuth2 clients to configure in Kanidm."
}

variable "kanidm_groups" {
  type = list(object({
    name    = string
    members = optional(list(string))
  }))
  default     = []
  description = "List of groups to create in Kanidm."
}

variable "kanidm_argo_workflows_oauth_enabled" {
  type        = bool
  default     = false
  description = "Enable OAuth2 integration between Argo Workflows and Kanidm."
}

# k8up variables
variable "k8up_enabled" {
  type        = bool
  default     = false
  description = "Enable k8up backup operator for Kubernetes backup and restore operations"
}

variable "k8up_helm_repository" {
  type        = string
  default     = "https://k8up-io.github.io/k8up"
  description = "Helm repository URL for k8up chart"
}

variable "k8up_helm_chart" {
  type        = string
  default     = "k8up"
  description = "Name of the k8up Helm chart"
}

variable "k8up_helm_version" {
  type        = string
  default     = "4.8.6"
  description = "Version of the k8up Helm chart to deploy"
}

variable "k8up_helm_values" {
  type        = any
  default     = {}
  description = "Additional Helm values to merge with k8up configuration"
}

# Prometheus Push Gateway
variable "pushgateway_helm_repository" {
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
  description = "Helm repository URL for Prometheus Push Gateway chart"
}

variable "pushgateway_helm_chart" {
  type        = string
  default     = "prometheus-pushgateway"
  description = "Name of the Prometheus Push Gateway Helm chart"
}

variable "pushgateway_helm_version" {
  type        = string
  default     = "3.4.1"
  description = "Version of the Prometheus Push Gateway Helm chart to deploy"
}

variable "pushgateway_helm_values" {
  type        = any
  default     = {}
  description = "Additional Helm values to merge with Prometheus Push Gateway configuration"
}

# Flux
variable "flux_enabled" {
  type        = bool
  default     = false
  description = "Enables the deployment of Flux CD GitOps toolkit."
}

variable "flux_helm_repository" {
  type        = string
  default     = "https://fluxcd-community.github.io/helm-charts"
  description = "URL of the Helm repository where the Flux chart is located."
}

variable "flux_helm_chart" {
  type        = string
  default     = "flux2"
  description = "Name of the Helm chart used for deploying Flux."
}

variable "flux_helm_version" {
  type        = string
  default     = "2.17.0"
  description = "Version of the Flux Helm chart to deploy."
}

variable "flux_helm_values" {
  type        = any
  default     = {}
  description = "Custom Helm values for the Flux chart deployment. These values will merge with and will override the default values provided by the Flux Helm chart."
}

variable "flux_watch_all_namespaces" {
  type        = bool
  default     = true
  description = "If true, Flux will watch for resources in all namespaces. Set to false for multi-tenancy scenarios."
}

variable "flux_log_level" {
  type        = string
  default     = "info"
  description = "Log level for Flux controllers (debug, info, error)."
}

variable "flux_image_automation_enabled" {
  type        = bool
  default     = true
  description = "Enable Flux image automation controllers for automatic image updates."
}

variable "flux_prometheus_podmonitor_enabled" {
  type        = bool
  default     = true
  description = "Enable Prometheus PodMonitor for Flux controllers metrics."
}
