mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

override_data {
  target = data.kubernetes_secret.admin_token[0]
  values = {
    data = { token = "sa-token-placeholder" }
  }
}

variables {
  agent    = { create = false }
  agent_id = "agent-existing"
  hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
  helm     = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

run "kubectl_connection_uses_service_account_token" {
  command = apply

  variables {
    kubernetes_admin = {}
  }

  assert {
    condition     = kubernetes_service_account.admin[0].metadata[0].name == "hoop-cluster-admin" && kubernetes_cluster_role_binding.admin[0].metadata[0].name == "hoop-cluster-admin" && kubernetes_secret.admin_token[0].metadata[0].name == "hoop-cluster-admin-token"
    error_message = "Default object names must stay identical to the ones already deployed."
  }

  assert {
    condition     = kubernetes_cluster_role_binding.admin[0].role_ref[0].name == "cluster-admin"
    error_message = "The binding defaults to cluster-admin."
  }

  assert {
    condition     = hoop_connection.this["k8s-admin"].secrets["envvar:HEADER_AUTHORIZATION"] == "Bearer sa-token-placeholder" && hoop_connection.this["k8s-admin"].secrets["envvar:KUBECTL_NAMESPACE"] == "paragon" && hoop_connection.this["k8s-admin"].access_mode_connect == "enabled"
    error_message = "The connection must authenticate with the ServiceAccount token against the in-cluster API."
  }
}

run "shared_cluster_suffix_and_extra_secrets" {
  command = apply

  variables {
    kubernetes_admin = {
      resource_suffix   = "-staging"
      name              = "acme-k8s-admin"
      kubectl_namespace = "app"
      extra_secrets     = { "envvar:AWS_ROLE_ARN" = "arn:aws:iam::123456789012:role/hoop-support" }
    }
  }

  assert {
    condition     = kubernetes_cluster_role_binding.admin[0].metadata[0].name == "hoop-cluster-admin-staging"
    error_message = "The cluster-scoped binding needs a per-agent suffix when clusters are shared."
  }

  assert {
    condition     = hoop_connection.this["k8s-admin"].name == "acme-k8s-admin" && hoop_connection.this["k8s-admin"].secrets["envvar:AWS_ROLE_ARN"] == "arn:aws:iam::123456789012:role/hoop-support"
    error_message = "Connection overrides and extra secrets must be forwarded."
  }
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_service_account.admin) == 0 && length(hoop_connection.this) == 0
    error_message = "Without kubernetes_admin the module must not create cluster objects or connections."
  }
}
