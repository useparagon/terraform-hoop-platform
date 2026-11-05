mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

# No helm version or image is given, so the module defaults apply.
variables {
  agent      = { create = false }
  agent_id   = "agent-existing"
  hoop_key   = "grpcs://agent:placeholder@example.test?mode=standard"
  helm       = { namespace = "paragon" }
  defaults   = { access_control_groups = [], postgres_guardrail_rules = [], redis_guardrail_rules = [] }
}

run "helm_defaults" {
  command = plan

  assert {
    condition     = helm_release.agent.version == "1.184.2" && contains([for setting in helm_release.agent.set : "${setting.name}=${setting.value}"], "image.repository=useparagon/hoop-agent-tools") && contains([for setting in helm_release.agent.set : "${setting.name}=${setting.value}"], "image.tag=1.2.1")
    error_message = "The chart version and the Paragon agent image must be the defaults."
  }
}
