# Deploy the Kubernetes agent. Cloud identity (IRSA, Azure workload identity, GKE
# workload identity) is created by the caller and passed in through
# helm.service_account.annotations; this module stays cloud-agnostic.
resource "helm_release" "agent" {
  name             = var.helm.name
  repository       = "oci://ghcr.io/hoophq/helm-charts"
  chart            = "hoopagent-chart"
  version          = var.helm.version
  namespace        = var.helm.namespace
  create_namespace = var.helm.create_namespace

  values          = concat([local.service_account_values], var.helm.values)
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm.timeout

  # Helm set values take precedence over chart defaults and values YAML.
  # Require the caller's pinned Paragon image rather than the chart default.
  set {
    name  = "image.repository"
    value = var.helm.image_repository
    type  = "string"
  }

  set {
    name  = "image.tag"
    value = var.helm.image_tag
    type  = "string"
  }

  set_sensitive {
    name  = "config.HOOP_KEY"
    value = local.hoop_key
    type  = "string"
  }

  lifecycle {
    precondition {
      condition     = local.agent_registered || (var.hoop_key != null) != (var.agent_key != null)
      error_message = "Set exactly one of hoop_key or agent_key when agent.create is false."
    }
    precondition {
      condition     = local.agent_registered || var.agent_id != null
      error_message = "agent_id is required when agent.create is false."
    }
  }
}
