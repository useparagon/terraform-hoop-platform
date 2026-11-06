locals {
  # Paragon's gateway is the default; set grpc_server to point elsewhere.
  grpc_server = coalesce(var.grpc_server, "hoop-grpc.ops.paragoninternal.com:8443")

  # The registered agent wins; otherwise the caller supplies the key whole or in parts.
  hoop_key = (
    local.agent_registered ? local.registered_hoop_key :
    var.agent_key == null ? var.hoop_key :
    "grpcs://${var.agent_key.name}:${var.agent_key.token}@${coalesce(var.agent_key.server, local.grpc_server)}?mode=${var.agent_key.mode}"
  )

  agent_registered    = var.agent.create
  registered_dsn      = local.agent_registered ? jsondecode(terracurl_request.agent[0].sensitive_response).token : null
  registered_parts    = local.agent_registered ? regex("^[a-z0-9+.-]+://(?P<name>[^:]+):(?P<token>[^@]+)@(?P<server>[^?]+)(?:\\?mode=(?P<mode>.+))?$", local.registered_dsn) : null
  registered_hoop_key = local.agent_registered ? "grpcs://${local.registered_parts.name}:${local.registered_parts.token}@${local.grpc_server}?mode=${coalesce(local.registered_parts.mode, var.agent.mode)}" : null
  agent_id            = local.agent_registered ? jsondecode(data.http.agent[0].response_body).id : var.agent_id

  # The agent image and its key. yamlencode keeps the key out of the plan diff
  # the same way a sensitive value does: the whole values list is sensitive
  # once it contains one.
  agent_values = yamlencode({
    image = {
      repository = var.helm.image_repository
      tag        = var.helm.image_tag
    }
    config = {
      HOOP_KEY = local.hoop_key
    }
  })

  # Chart values that carry the ServiceAccount (and its workload-identity annotations).
  # Placed first so values supplied by the caller in helm.values can still override them.
  service_account_values = yamlencode({
    serviceAccount = merge(
      { create = var.helm.service_account.create },
      var.helm.service_account.name != null ? { name = var.helm.service_account.name } : {},
      length(var.helm.service_account.annotations) > 0 ? { annotations = var.helm.service_account.annotations } : {},
    )
  })

  postgres_connections = {
    for key, conn in var.postgres : "postgres-${key}" => {
      name                   = conn.name
      type                   = "database"
      subtype                = "postgres"
      command                = null
      jira_issue_template_id = null
      secrets = {
        "envvar:HOST"    = conn.host
        "envvar:PORT"    = tostring(conn.port)
        "envvar:USER"    = conn.user
        "envvar:PASS"    = conn.password
        "envvar:DB"      = conn.database
        "envvar:SSLMODE" = conn.sslmode
      }
      tags                  = conn.tags
      guardrail_rules       = length(conn.guardrail_rules) > 0 ? conn.guardrail_rules : var.defaults.postgres_guardrail_rules
      reviewers             = conn.reviewers
      access_control_groups = conn.access_control_groups
      access_mode_runbooks  = "enabled"
      access_mode_exec      = "enabled"
      access_mode_connect   = conn.access_mode_connect
      access_schema         = conn.access_schema
    }
  }

  redis_connections = {
    for key, conn in var.redis : "redis-${key}" => {
      name                   = conn.name
      type                   = "custom"
      subtype                = "redis"
      jira_issue_template_id = null
      command = conn.command != null ? conn.command : concat(
        ["redis-cli", "-c", "-h", "$HOST", "-p", "$PORT", "-n", "$DB_NUMBER"],
        conn.ssl ? ["--tls"] : [],
        conn.ssl && conn.ca_certificate != null ? ["--cacert", "$REDIS_CACERT_PATH"] : []
      )
      secrets = merge(
        conn.extra_secrets,
        {
          "envvar:HOST"      = conn.host
          "envvar:PORT"      = tostring(conn.port)
          "envvar:DB_NUMBER" = tostring(conn.db_number)
        },
        conn.password != null ? { "envvar:REDISCLI_AUTH" = conn.password } : {},
        conn.ssl && conn.ca_certificate != null ? { "filesystem:REDIS_CACERT_PATH" = conn.ca_certificate } : {}
      )
      tags                  = conn.tags
      guardrail_rules       = length(conn.guardrail_rules) > 0 ? conn.guardrail_rules : var.defaults.redis_guardrail_rules
      reviewers             = conn.reviewers
      access_control_groups = conn.access_control_groups
      access_mode_runbooks  = "enabled"
      access_mode_exec      = "enabled"
      access_mode_connect   = conn.access_mode_connect
      access_schema         = "disabled"
    }
  }

  duplicate_connection_keys = setintersection(
    toset(nonsensitive(keys(var.connections))),
    setunion(
      toset(nonsensitive(keys(local.postgres_connections))),
      toset(nonsensitive(keys(local.redis_connections))),
    )
  )

  kubernetes_admin_enabled = var.kubernetes_admin.enabled

  # An EKS kubectl session starts with a clean environment, so the ServiceAccount's
  # IRSA variables never reach it. Injecting them is what makes the session assume
  # the support role. AKS and GKE authenticate without this, so they set irsa = false.
  irsa_role_arn = try(var.helm.service_account.annotations["eks.amazonaws.com/role-arn"], null)
  irsa_secrets = var.kubernetes_admin.irsa && local.irsa_role_arn != null ? {
    "envvar:AWS_ROLE_ARN"                = local.irsa_role_arn
    "envvar:AWS_WEB_IDENTITY_TOKEN_FILE" = "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
  } : {}

  kubernetes_admin_connection = local.kubernetes_admin_enabled ? {
    "k8s-admin" = {
      name    = coalesce(var.kubernetes_admin.name, "k8s-admin")
      type    = "custom"
      subtype = null
      command = ["bash"]
      secrets = merge(
        var.kubernetes_admin.extra_secrets,
        local.irsa_secrets,
        {
          "envvar:REMOTE_URL"           = var.kubernetes_admin.remote_url
          "envvar:INSECURE"             = tostring(var.kubernetes_admin.insecure)
          "envvar:KUBECTL_NAMESPACE"    = coalesce(var.kubernetes_admin.kubectl_namespace, var.helm.namespace)
          "envvar:HEADER_AUTHORIZATION" = "Bearer ${try(data.kubernetes_secret.admin_token[0].data["token"], "")}"
        },
      )
      tags                   = var.kubernetes_admin.tags
      guardrail_rules        = var.kubernetes_admin.guardrail_rules
      reviewers              = var.kubernetes_admin.reviewers
      access_control_groups  = var.kubernetes_admin.access_control_groups
      access_mode_runbooks   = var.kubernetes_admin.access_mode_runbooks
      access_mode_exec       = var.kubernetes_admin.access_mode_exec
      access_mode_connect    = var.kubernetes_admin.access_mode_connect
      access_schema          = "disabled"
      jira_issue_template_id = null
    }
  } : {}

  # Caller entries first, then the shared policy from var.defaults fills the gaps.
  merged_connections = merge(var.connections, local.postgres_connections, local.redis_connections, local.kubernetes_admin_connection)

  all_connections = {
    for key, conn in local.merged_connections : key => merge(conn, {
      tags = merge(
        { environment = var.environment == "production" ? "prod" : "staging" },
        var.defaults.tags,
        conn.tags,
      )
      access_control_groups = (
        length(conn.access_control_groups) > 0
        ? conn.access_control_groups
        : var.defaults.access_control_groups
      )
    })
  }

  connection_names = [for key, conn in local.all_connections : nonsensitive(coalesce(conn.name, key))]

  # Terraform resource keys and filter fields cannot be sensitive. The caller
  # must use non-secret identifiers, types, reviewer groups and access groups.
  # Connection secrets themselves remain sensitive.
  connection_keys = toset(nonsensitive(keys(local.all_connections)))

  postgres_connection_keys = toset([
    for key in local.connection_keys : key
    if lower(nonsensitive(local.all_connections[key].type)) == "database" && contains(["postgres", "postgresql"], try(lower(nonsensitive(local.all_connections[key].subtype)), ""))
  ])

  standard_connection_keys = setsubtract(local.connection_keys, local.postgres_connection_keys)

  access_control_keys = toset([
    for key in local.connection_keys : key
    if length(nonsensitive(local.all_connections[key].access_control_groups)) > 0
  ])

  # Reviewers are who Slack notifies. An empty config keeps the channel Ops
  # already set on the Hoop organization; this module does not own that plugin.
  slack_keys = toset([
    for key in local.connection_keys : key
    if length(nonsensitive(local.all_connections[key].reviewers)) > 0
  ])

  connection_ids = merge(
    { for key, connection in hoop_connection.this : key => connection.id },
    { for key, connection in hoop_connection.postgres : key => connection.id },
  )
}
