variable "hoop_key" {
  description = "Complete agent HOOP_KEY value, such as grpcs://agent-name:token@gateway.example.com?mode=standard. The caller constructs it using its existing secret source; this is NOT the Hoop provider API key."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.hoop_key)) > 0
    error_message = "hoop_key must not be empty."
  }
}

variable "helm" {
  description = "Helm release configuration. Set namespace, chart version, and the Paragon-built agent image repository (including its registry when needed) and immutable image tag explicitly. The chart version and agent image tag are independent. Additional Helm values configure service accounts and cloud workload identities."
  type = object({
    namespace        = string
    version          = string
    image_repository = string
    image_tag        = string
    name             = optional(string, "hoopagent")
    create_namespace = optional(bool, false)
    values           = optional(list(string), [])
    timeout          = optional(number, 300)
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

variable "agent_id" {
  description = "ID of an existing Hoop agent registration in the Hoop platform. The module installs its Kubernetes runtime via Helm but does not create or change the platform agent registration."
  type        = string

  validation {
    condition     = length(trimspace(var.agent_id)) > 0
    error_message = "agent_id must be a non-empty existing agent ID."
  }
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
