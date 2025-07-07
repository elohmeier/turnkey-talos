# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform-based infrastructure-as-code project for deploying production-ready Kubernetes clusters on Hetzner Cloud using Talos Linux. It provides a complete "turnkey" solution with integrated monitoring, logging, storage, and GitOps capabilities.

## Common Commands

### Terraform Operations
```bash
# Initialize Terraform providers and modules
terraform init

# Plan changes (always use a tfvars file)
terraform plan -var-file="terraform.tfvars"

# Apply configuration
terraform apply -var-file="terraform.tfvars"

# Destroy infrastructure (be careful!)
terraform destroy -var-file="terraform.tfvars"

# Format Terraform files (enforced by pre-commit)
terraform fmt -recursive

# Validate Terraform configuration
terraform validate
```

### Development Tools
```bash
# Run pre-commit hooks manually
pre-commit run --all-files

# Install pre-commit hooks
pre-commit install
```

### Cluster Access
```bash
# Use generated kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes

# Access Talos nodes
talosctl --talosconfig ./talosconfig health

# Access MinIO S3 storage
mc --config-dir ./.mc ls s3/
```

## Architecture & Code Structure

### Module-Based Architecture
The project uses the `terraform-hcloud-kubernetes` module from `github.com/elohmeier/terraform-hcloud-kubernetes` as its foundation, then layers additional components on top.

### Component Pattern
Each component follows a consistent implementation pattern:
1. **Local configuration block** - defines component-specific variables
2. **Conditional deployment** - uses `*_enabled` variables for optional features
3. **Helm chart deployment** - standardized Helm resource definitions
4. **Cross-component integration** - components reference each other when enabled

Example pattern from argocd.tf:
```hcl
locals {
  argocd = {
    enabled = var.argocd_enabled
    # component configuration
  }
}

resource "helm_release" "argocd" {
  count = local.argocd.enabled ? 1 : 0
  # helm deployment
}
```

### Key Integration Points

1. **S3 Storage Backend**: Used by Longhorn, Talos backups, and Argo Workflows. Configured via MinIO provider pointing to `${location}.your-objectstorage.com`.

2. **Monitoring Stack**: VictoriaMetrics collects metrics from all components via ServiceMonitors. VictoriaLogs aggregates logs. Grafana provides visualization.

3. **Ingress Architecture**: When Tailscale is enabled, it becomes the primary ingress. Otherwise, NGINX ingress is used. Services expose through standardized ingress patterns.

4. **GitOps Flow**: Argo CD manages deployments. Components can be deployed either via Terraform or Argo CD applications.

### Critical Dependencies

- **Terraform >= 1.7.0** required
- **Hetzner Cloud API token** must have full access
- **S3-compatible storage** required for backups
- **Tailscale OAuth** credentials needed when Tailscale is enabled

### Variable Validation Patterns

The project uses extensive Terraform validation rules:
- Node counts must be odd for control planes (etcd quorum)
- Resource constraints are validated (CPU/memory)
- Conditional validations based on enabled features

## Development Considerations

### Pre-commit Hooks
Always ensure pre-commit hooks pass before committing:
- `terraform fmt` - enforces consistent formatting
- `check-yaml` - validates YAML syntax
- `trailing-whitespace` - removes trailing spaces
- `check-added-large-files` - prevents accidental large file commits

### State Management
- Terraform state should be stored remotely (not included in repo)
- Use state locking to prevent concurrent modifications
- Never commit `.tfstate` files

### Testing Approach
When modifying components:
1. Test with minimal configuration first (`*_enabled = false` for most components)
2. Enable components incrementally
3. Verify integrations work (e.g., metrics appear in Grafana)
4. Check generated URLs in outputs

### Common Modifications

1. **Adding a new component**: Create a new `.tf` file following the existing pattern
2. **Modifying Helm values**: Update the `values` list in the respective `helm_release` resource
3. **Adding monitoring**: Include ServiceMonitor resources and Grafana dashboards
4. **Updating versions**: Change chart versions in `helm_release` resources

### Debugging Tips

- Check Helm release status: `helm list -A`
- View Terraform state: `terraform state list`
- Inspect specific resources: `terraform state show <resource>`
- Debug Talos issues: `talosctl --talosconfig ./talosconfig dmesg`
- Check Argo CD sync status if GitOps is enabled
