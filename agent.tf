# Deploy the Kubernetes agent. Cloud-specific identity, RBAC and chart values belong to the caller.
resource "helm_release" "agent" {
  name             = var.helm.name
  repository       = "oci://ghcr.io/hoophq/helm-charts"
  chart            = "hoopagent-chart"
  version          = var.helm.version
  namespace        = var.helm.namespace
  create_namespace = var.helm.create_namespace

  values          = var.helm.values
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
    value = var.hoop_key
    type  = "string"
  }
}
