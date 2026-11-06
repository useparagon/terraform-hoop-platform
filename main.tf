# Shared Hoop connection resources. Connection definitions and secret sources are caller-owned.
resource "hoop_connection" "this" {
  for_each = local.standard_connection_keys

  name     = nonsensitive(coalesce(local.all_connections[each.key].name, each.key))
  type     = nonsensitive(local.all_connections[each.key].type)
  agent_id = local.agent_id

  subtype                = local.all_connections[each.key].subtype
  jira_issue_template_id = local.all_connections[each.key].jira_issue_template_id
  command                = local.all_connections[each.key].command

  access_mode_runbooks = local.all_connections[each.key].access_mode_runbooks
  access_mode_exec     = local.all_connections[each.key].access_mode_exec
  access_mode_connect  = local.all_connections[each.key].access_mode_connect
  access_schema        = local.all_connections[each.key].access_schema

  guardrail_rules = length(local.all_connections[each.key].guardrail_rules) > 0 ? local.all_connections[each.key].guardrail_rules : null
  reviewers       = length(local.all_connections[each.key].reviewers) > 0 ? local.all_connections[each.key].reviewers : null
  secrets         = length(local.all_connections[each.key].secrets) > 0 ? local.all_connections[each.key].secrets : null
  tags            = length(local.all_connections[each.key].tags) > 0 ? local.all_connections[each.key].tags : null

  lifecycle {
    precondition {
      condition     = length(local.duplicate_connection_keys) == 0
      error_message = "Duplicate Hoop connection keys across connections/postgres/redis are not allowed."
    }
    precondition {
      condition     = length(local.connection_names) == length(distinct(local.connection_names))
      error_message = "Hoop connection names must be unique across connections/postgres/redis."
    }
  }
}

# Hoop normalizes PostgreSQL commands. Retain the existing ignore_changes behavior.
resource "hoop_connection" "postgres" {
  for_each = local.postgres_connection_keys

  name     = nonsensitive(coalesce(local.all_connections[each.key].name, each.key))
  type     = nonsensitive(local.all_connections[each.key].type)
  agent_id = local.agent_id

  subtype                = local.all_connections[each.key].subtype
  jira_issue_template_id = local.all_connections[each.key].jira_issue_template_id
  command                = local.all_connections[each.key].command

  access_mode_runbooks = local.all_connections[each.key].access_mode_runbooks
  access_mode_exec     = local.all_connections[each.key].access_mode_exec
  access_mode_connect  = local.all_connections[each.key].access_mode_connect
  access_schema        = local.all_connections[each.key].access_schema

  guardrail_rules = length(local.all_connections[each.key].guardrail_rules) > 0 ? local.all_connections[each.key].guardrail_rules : null
  reviewers       = length(local.all_connections[each.key].reviewers) > 0 ? local.all_connections[each.key].reviewers : null
  secrets         = length(local.all_connections[each.key].secrets) > 0 ? local.all_connections[each.key].secrets : null
  tags            = length(local.all_connections[each.key].tags) > 0 ? local.all_connections[each.key].tags : null

  lifecycle {
    ignore_changes = [command]

    precondition {
      condition     = length(local.duplicate_connection_keys) == 0
      error_message = "Duplicate Hoop connection keys across connections/postgres/redis are not allowed."
    }
    precondition {
      condition     = length(local.connection_names) == length(distinct(local.connection_names))
      error_message = "Hoop connection names must be unique across connections/postgres/redis."
    }
  }
}

resource "hoop_plugin_connection" "access_control" {
  for_each = local.access_control_keys

  plugin_name   = "access_control"
  connection_id = local.connection_ids[each.key]
  config        = local.all_connections[each.key].access_control_groups
}

resource "hoop_plugin_connection" "slack" {
  for_each = local.slack_keys

  plugin_name   = "slack"
  connection_id = local.connection_ids[each.key]
  config        = []
}
