variable "hoop_key" {
  description = "Complete agent HOOP_KEY value, such as grpcs://agent-name:token@gateway.example.com?mode=standard. Set exactly one of hoop_key or agent_key. This is NOT the Hoop provider API key."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.hoop_key == null || length(trimspace(var.hoop_key)) > 0
    error_message = "hoop_key must not be empty when set."
  }
}

variable "grpc_server" {
  description = "Hoop gRPC gateway address (host:port) used when the module assembles the HOOP_KEY. Null uses Paragon's gateway."
  type        = string
  default     = null
}

variable "agent_key" {
  description = "Agent key as separate parts. The module assembles grpcs://<name>:<token>@<server>?mode=<mode>. Use it when the token and the gateway address come from different sources. server defaults to grpc_server. Set exactly one of hoop_key or agent_key when agent.create is false."
  type = object({
    name   = string
    token  = string
    server = optional(string)
    mode   = optional(string, "standard")
  })
  sensitive = true
  default   = null

  validation {
    condition = var.agent_key == null || alltrue([
      length(trimspace(var.agent_key.name)) > 0,
      length(trimspace(var.agent_key.token)) > 0,
    ])
    error_message = "agent_key.name and agent_key.token must not be empty."
  }
}

variable "helm" {
  description = "Helm release configuration. Set namespace, chart version, and the Paragon-built agent image repository (including its registry when needed) and immutable image tag explicitly. The chart version and agent image tag are independent. service_account carries cloud workload-identity annotations (eks.amazonaws.com/role-arn, azure.workload.identity/client-id, iam.gke.io/gcp-service-account); values adds any further chart values."
  type = object({
    namespace        = string
    version          = string
    image_repository = string
    image_tag        = string
    name             = optional(string, "hoopagent")
    create_namespace = optional(bool, false)
    values           = optional(list(string), [])
    timeout          = optional(number, 300)
    service_account = optional(object({
      create      = optional(bool, true)
      name        = optional(string)
      annotations = optional(map(string), {})
    }), {})
  })

  validation {
    condition = alltrue([
      length(trimspace(var.helm.namespace)) > 0,
      length(trimspace(var.helm.version)) > 0,
      length(trimspace(var.helm.image_repository)) > 0,
      length(trimspace(var.helm.image_tag)) > 0,
      var.helm.timeout > 0,
    ])
    error_message = "helm.namespace, helm.version, helm.image_repository and helm.image_tag must not be empty; helm.timeout must be greater than zero."
  }
}

variable "agent_name" {
  description = "Name of the Hoop agent. It becomes part of the HOOP_KEY, so use a stable, environment-identifying name (for example example-agent). Required when the module registers the agent (agent.create = true)."
  type        = string
  default     = null

  validation {
    condition     = var.agent_name == null || length(trimspace(var.agent_name)) > 0
    error_message = "agent_name must not be empty when set."
  }
}

variable "agent" {
  description = <<-EOT
    Agent registration in the Hoop platform. The same for every caller.

    create = true (default): the module registers the agent through the Hoop API and removes it on destroy. api_key is required; api_url defaults to Paragon's Hoop API. agent_id and agent_key come from the registration.
    create = false: the agent already exists and Hoop will not issue its key again. The module does not call the API, and the caller supplies agent_id and agent_key (or hoop_key).
  EOT
  type = object({
    create  = optional(bool, true)
    api_url = optional(string, "https://hoop.ops.paragoninternal.com/api")
    api_key = optional(string)
    mode    = optional(string, "standard")
  })
  default = {}

  validation {
    condition = (
      !var.agent.create ||
      (
        var.agent.api_url != null && startswith(var.agent.api_url, "https://") && !endswith(var.agent.api_url, "/") &&
        var.agent.api_key != null && startswith(var.agent.api_key, "hpk_")
      )
    )
    error_message = "When agent.create is true, agent.api_url must be an https URL without a trailing slash and agent.api_key must be an hpk_ key."
  }
}

variable "agent_id" {
  description = "ID of an agent that already exists in Hoop. Required when agent.create is false; ignored when the module registers the agent."
  type        = string
  default     = null

  validation {
    condition     = var.agent_id == null || length(trimspace(var.agent_id)) > 0
    error_message = "agent_id must not be empty when set."
  }
}

variable "kubernetes_admin" {
  description = <<-EOT
    kubectl connection backed by a ServiceAccount, a ClusterRoleBinding and a token Secret. null disables it.

    The ClusterRoleBinding is cluster-scoped, so set resource_suffix when several agents share one cluster. extra_secrets adds connection secrets beyond the token, such as the IRSA environment variables a kubectl session needs to assume the support role.
  EOT
  type = object({
    enabled               = optional(bool, true)
    service_account_name  = optional(string, "hoop-cluster-admin")
    token_secret_name     = optional(string, "hoop-cluster-admin-token")
    cluster_role          = optional(string, "cluster-admin")
    resource_suffix       = optional(string, "")
    token_wait_duration   = optional(string, "10s")
    name                  = optional(string)
    remote_url            = optional(string, "https://kubernetes.default.svc.cluster.local")
    insecure              = optional(bool, true)
    kubectl_namespace     = optional(string)
    extra_secrets         = optional(map(string), {})
    tags                  = optional(map(string), {})
    guardrail_rules       = optional(list(string), [])
    reviewers             = optional(list(string), [])
    access_control_groups = optional(list(string), [])
    access_mode_runbooks  = optional(string, "enabled")
    access_mode_exec      = optional(string, "enabled")
    access_mode_connect   = optional(string, "enabled")
  })
  default = null
}

variable "defaults" {
  description = <<-EOT
    Policy applied to every connection that does not set its own value, so each caller states its access policy once instead of repeating it per connection.

    access_control_groups: groups attached to connections whose access_control_groups is empty. Defaults to the groups used across deployments (dev-team-oncall, dev-team-managers, admin).
    postgres_guardrail_rules / redis_guardrail_rules: guardrails for the typed postgres / redis inputs when the entry sets none. Defaults to the shared guardrail rule IDs.
    tags: merged under each connection's own tags (connection tags win).
  EOT
  type = object({
    access_control_groups    = optional(list(string), ["dev-team-oncall", "dev-team-managers", "admin"])
    postgres_guardrail_rules = optional(list(string), ["a85115f6-5ef3-4618-b70c-f7cccdc62c5a"])
    redis_guardrail_rules    = optional(list(string), ["182f59b2-5d5d-4ab8-978e-94472b3915fc"])
    tags                     = optional(map(string), {})
  })
  default = {}
}

variable "connections" {
  description = <<-EOT
    Optional advanced Hoop connections, keyed by stable, non-secret Terraform identifiers. Defaults to an empty map (no connections). For ordinary PostgreSQL and Redis use postgres and redis inputs instead. The consuming workspace prepares every entry using its own Terraform locals, configuration and secret sources; this module does not need to know the cloud.

    Required field per entry: type (database, application or custom).
    Optional fields: name (defaults to the map key), subtype (e.g. postgres, redis or tcp), jira_issue_template_id (Hoop approval ticket template), command (argument list), secrets (Hoop-compatible envvar:/filesystem: values), tags, guardrail_rules, reviewers and access_control_groups.

    Access modes accept "enabled" or "disabled"; runbooks and exec default to "enabled", while connect and schema default to "disabled". Lists and maps default to empty. PostgreSQL database connections use a separate resource to ignore provider command normalization.

    The map itself is not marked sensitive so plans can display non-secret connection metadata. The Hoop provider marks secrets as sensitive; credentials may nevertheless remain in Terraform state. Inputs derived from an entirely sensitive source may still hide other fields in plans. Never use secrets as map keys, names, types, reviewers or access group names.
  EOT

  type = map(object({
    name                   = optional(string)
    type                   = string
    subtype                = optional(string)
    jira_issue_template_id = optional(string)
    command                = optional(list(string))
    secrets                = optional(map(string), {})
    tags                   = optional(map(string), {})
    guardrail_rules        = optional(list(string), [])
    reviewers              = optional(list(string), [])
    access_control_groups  = optional(list(string), [])

    access_mode_runbooks = optional(string, "enabled")
    access_mode_exec     = optional(string, "enabled")
    access_mode_connect  = optional(string, "disabled")
    access_schema        = optional(string, "disabled")
  }))
  default = {}

  validation {
    condition = alltrue([
      for conn in values(var.connections) : contains(["database", "application", "custom"], conn.type)
    ])
    error_message = "Connections must have type database, application or custom."
  }

  validation {
    condition = alltrue(flatten([
      for conn in values(var.connections) : [
        contains(["enabled", "disabled"], conn.access_mode_runbooks),
        contains(["enabled", "disabled"], conn.access_mode_exec),
        contains(["enabled", "disabled"], conn.access_mode_connect),
        contains(["enabled", "disabled"], conn.access_schema),
      ]
    ]))
    error_message = "Access-mode values must be enabled or disabled."
  }
}

variable "postgres" {
  description = "PostgreSQL connections keyed by stable names. Credentials and endpoints come from the Kubernetes caller's existing Terraform secret source. Each entry accepts host, port (default 5432), user, password, database, sslmode, tags, guardrails, reviewers and access groups."
  type = map(object({
    name                  = optional(string)
    host                  = string
    port                  = optional(number, 5432)
    user                  = string
    password              = string
    database              = string
    sslmode               = optional(string, "require")
    tags                  = optional(map(string), {})
    guardrail_rules       = optional(list(string), [])
    reviewers             = optional(list(string), [])
    access_control_groups = optional(list(string), [])
    access_mode_connect   = optional(string, "disabled")
    access_schema         = optional(string, "enabled")
  }))
  default = {}
}

variable "redis" {
  description = "Redis connections keyed by stable names. Each entry specifies host, port (default 6379), DB index, TLS/CA options and optional authentication. Override the CLI command when necessary; extra_secrets can add environment-specific keys but cannot override HOST, PORT, DB_NUMBER, REDISCLI_AUTH, or REDIS_CACERT_PATH. No cloud-specific logic is embedded in the module."
  type = map(object({
    name                  = optional(string)
    host                  = string
    port                  = optional(number, 6379)
    db_number             = optional(number, 0)
    password              = optional(string)
    ssl                   = optional(bool, false)
    ca_certificate        = optional(string)
    command               = optional(list(string))
    extra_secrets         = optional(map(string), {})
    tags                  = optional(map(string), {})
    guardrail_rules       = optional(list(string), [])
    reviewers             = optional(list(string), [])
    access_control_groups = optional(list(string), [])
    access_mode_connect   = optional(string, "disabled")
  }))
  default = {}

  validation {
    condition = alltrue([
      for conn in values(var.redis) :
      length(setintersection(
        toset(nonsensitive(keys(conn.extra_secrets))),
        toset([
          "envvar:HOST",
          "envvar:PORT",
          "envvar:DB_NUMBER",
          "envvar:REDISCLI_AUTH",
          "filesystem:REDIS_CACERT_PATH",
        ]),
      )) == 0
    ])
    error_message = "redis.extra_secrets must not override HOST, PORT, DB_NUMBER, REDISCLI_AUTH or REDIS_CACERT_PATH; use the typed Redis fields."
  }
}
