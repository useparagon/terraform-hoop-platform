mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

variables {
  agent            = { create = false }
  kubernetes_admin = { enabled = false }
  defaults         = { access_control_groups = [], postgres_guardrail_rules = [], redis_guardrail_rules = [] }
  hoop_key         = "grpcs://agent:placeholder@example.test?mode=standard"
  helm             = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

run "empty_connections" {
  command = plan

  variables {
    agent_id    = "agent-existing"
    connections = {}
  }

  assert {
    condition     = output.agent_id == "agent-existing"
    error_message = "The existing agent ID must be returned unchanged."
  }

  assert {
    condition     = length(output.connection_ids) == 0
    error_message = "An empty map must create no Hoop connections."
  }
}

run "postgres_and_standard" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      db = {
        type                  = "database"
        subtype               = "postgres"
        secrets               = { "envvar:HOST" = "db.example.test", "envvar:PASS" = "sensitive-test-placeholder" }
        access_control_groups = ["team"]
      }
      app = {
        type      = "application"
        subtype   = "tcp"
        reviewers = ["approvers"]
      }
    }
  }

  assert {
    condition     = length(hoop_connection.postgres) == 1 && length(hoop_connection.this) == 1
    error_message = "Postgres and standard connections must use their respective resource addresses."
  }

  assert {
    condition     = length(hoop_plugin_connection.access_control) == 1
    error_message = "Access Control should be attached only when groups are provided."
  }

  assert {
    condition     = length(hoop_plugin_connection.slack) == 1 && hoop_plugin_connection.slack["app"].plugin_name == "slack" && length(hoop_plugin_connection.slack["app"].config) == 0
    error_message = "Slack is attached only to connections with reviewers, and the config stays empty so the organization channel is used."
  }
}

run "postgres_subtype_aliases" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      pg_upper = { type = "database", subtype = "Postgres" }
      pg_long  = { type = "database", subtype = "PostgreSQL" }
      regular  = { type = "application", subtype = "tcp" }
    }
  }

  assert {
    condition     = length(hoop_connection.postgres) == 2 && length(hoop_connection.this) == 1
    error_message = "PostgreSQL subtype aliases must retain ignore_changes for normalized commands."
  }
}

run "helm_agent_uses_supplied_key" {
  command = plan
  variables {
    agent_id = "existing-agent-id"
  }
  assert {
    condition     = helm_release.agent.namespace == "paragon" && helm_release.agent.chart == "hoopagent-chart" && yamldecode(helm_release.agent.values[1]).image.repository == "useparagon/hoop-agent-tools" && yamldecode(helm_release.agent.values[1]).image.tag == "1.2.1"
    error_message = "Agent must use the generic Helm chart and caller namespace."
  }
}
