mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

override_resource {
  target = terracurl_request.agent[0]
  values = {
    sensitive_response = "{\"token\":\"grpcs://acme:tok-123@hoop-grpc.internal:8443?mode=standard\"}"
  }
}

override_data {
  target = data.http.agent[0]
  values = {
    status_code   = 200
    response_body = "{\"id\":\"11111111-2222-3333-4444-555555555555\",\"name\":\"acme\"}"
  }
}

variables {
  agent_name = "acme"
  agent      = { api_url = "https://hoop.example.test/api", api_key = "hpk_placeholder" }
  helm       = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

run "registers_agent_and_uses_its_key" {
  command = apply

  assert {
    condition     = terracurl_request.agent[0].url == "https://hoop.example.test/api/agents" && terracurl_request.agent[0].destroy_url == "https://hoop.example.test/api/agents/acme"
    error_message = "The agent must be created and destroyed by name through the Hoop API."
  }

  assert {
    condition     = output.agent_id == "11111111-2222-3333-4444-555555555555"
    error_message = "The agent UUID must come from the lookup by name."
  }

  assert {
    condition     = [for s in helm_release.agent.set_sensitive : s.value if s.name == "config.HOOP_KEY"][0] == "grpcs://acme:tok-123@hoop-grpc.ops.paragoninternal.com:8443?mode=standard"
    error_message = "The DSN returned at registration must become the agent HOOP_KEY."
  }
}

run "registration_requires_agent_name" {
  command = plan

  variables {
    agent_name = null
  }

  expect_failures = [terracurl_request.agent[0]]
}

run "registration_requires_hpk_key" {
  command = plan

  variables {
    agent = { api_url = "https://hoop.example.test/api", api_key = "legacy-key" }
  }

  expect_failures = [var.agent]
}

# An agent that already exists keeps its current ID and key.
run "existing_agent_is_left_untouched" {
  command = plan

  variables {
    agent_name = null
    agent      = { create = false }
    agent_id   = "agent-existing"
    hoop_key   = "grpcs://agent:placeholder@example.test?mode=standard"
  }

  assert {
    condition     = length(terracurl_request.agent) == 0 && length(data.http.agent) == 0
    error_message = "agent.create = false must not register or look up the agent."
  }

  assert {
    condition     = output.agent_id == "agent-existing"
    error_message = "The caller-supplied agent ID must be used."
  }
}

run "existing_agent_requires_id_and_key" {
  command = plan

  variables {
    agent_name = null
    agent      = { create = false }
  }

  expect_failures = [helm_release.agent]
}

# The Paragon API endpoint is the default, so callers only pass the key.
run "api_url_defaults_to_paragon" {
  command = plan

  variables {
    agent = { api_key = "hpk_placeholder" }
  }

  assert {
    condition     = terracurl_request.agent[0].url == "https://hoop.ops.paragoninternal.com/api/agents"
    error_message = "agent.api_url must default to Paragon's Hoop API."
  }
}
