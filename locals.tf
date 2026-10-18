locals {
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
      guardrail_rules       = conn.guardrail_rules
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
      guardrail_rules       = conn.guardrail_rules
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

  all_connections  = merge(var.connections, local.postgres_connections, local.redis_connections)
  connection_names = [for key, conn in local.all_connections : nonsensitive(coalesce(conn.name, key))]

  # Terraform resource keys and filter fields cannot be sensitive. The caller
  # must use non-secret identifiers, types, reviewer groups and access groups.
  # Connection secrets themselves remain sensitive.
  connection_keys = toset(nonsensitive(keys(local.all_connections)))

  postgres_connection_keys = toset([
    for key in local.connection_keys : key
    if lower(nonsensitive(local.all_connections[key].type)) == "database" && contains(["postgres", "postgresql"], lower(coalesce(nonsensitive(local.all_connections[key].subtype), "")))
  ])

  standard_connection_keys = setsubtract(local.connection_keys, local.postgres_connection_keys)

  access_control_keys = toset([
    for key in local.connection_keys : key
    if length(nonsensitive(local.all_connections[key].access_control_groups)) > 0
  ])

  connection_ids = merge(
    { for key, connection in hoop_connection.this : key => connection.id },
    { for key, connection in hoop_connection.postgres : key => connection.id },
  )
}
