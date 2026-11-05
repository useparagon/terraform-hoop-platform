# ServiceAccount, RBAC and token used by the kubectl connection. Every consumer
# needs the same objects, so they live here once. Cloud identity for the agent pod
# itself arrives through helm.service_account.annotations.
resource "kubernetes_service_account" "admin" {
  count = local.kubernetes_admin_enabled ? 1 : 0

  metadata {
    name      = var.kubernetes_admin.service_account_name
    namespace = var.helm.namespace
  }
}

resource "kubernetes_cluster_role_binding" "admin" {
  count = local.kubernetes_admin_enabled ? 1 : 0

  metadata {
    name = "${var.kubernetes_admin.service_account_name}${var.kubernetes_admin.resource_suffix}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = var.kubernetes_admin.cluster_role
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.admin[0].metadata[0].name
    namespace = var.helm.namespace
  }
}

resource "kubernetes_secret" "admin_token" {
  count = local.kubernetes_admin_enabled ? 1 : 0

  metadata {
    name      = var.kubernetes_admin.token_secret_name
    namespace = var.helm.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.admin[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"

  # The token controller fills the Secret asynchronously; block until it does.
  wait_for_service_account_token = true
}

resource "time_sleep" "admin_token" {
  count = local.kubernetes_admin_enabled ? 1 : 0

  create_duration = var.kubernetes_admin.token_wait_duration

  depends_on = [kubernetes_secret.admin_token]
}

data "kubernetes_secret" "admin_token" {
  count = local.kubernetes_admin_enabled ? 1 : 0

  metadata {
    name      = kubernetes_secret.admin_token[0].metadata[0].name
    namespace = var.helm.namespace
  }

  depends_on = [time_sleep.admin_token]

  # An empty token would become "Bearer " in the connection and only fail on first use.
  lifecycle {
    postcondition {
      condition     = length(try(self.data["token"], "")) > 0
      error_message = "The ${var.kubernetes_admin.service_account_name} ServiceAccount token is empty; rerun apply once the token controller has populated the Secret."
    }
  }
}
