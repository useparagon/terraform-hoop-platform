mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

# No helm version or image is given, so the module defaults apply.
variables {
  agent            = { create = false }
  agent_id         = "agent-existing"
  hoop_key         = "grpcs://agent:placeholder@example.test?mode=standard"
  helm             = {}
  kubernetes_admin = { enabled = false }
  defaults         = { access_control_groups = [], postgres_guardrail_rules = [], redis_guardrail_rules = [] }
}

run "helm_defaults" {
  command = plan

  assert {
    condition     = helm_release.agent.version == "1.184.2" && yamldecode(helm_release.agent.values[1]).image.repository == "useparagon/hoop-agent-tools" && yamldecode(helm_release.agent.values[1]).image.tag == "1.2.1"
    error_message = "The chart version and the Paragon agent image must be the defaults."
  }

  assert {
    condition     = helm_release.agent.namespace == "paragon"
    error_message = "The agent must land in the paragon namespace by default."
  }
}

run "environment_tag" {
  command = plan

  variables {
    environment = "production"
    connections = { grafana = { type = "application", subtype = "tcp" } }
  }

  assert {
    condition     = hoop_connection.this["grafana"].tags["environment"] == "prod"
    error_message = "production must be tagged as prod."
  }
}
