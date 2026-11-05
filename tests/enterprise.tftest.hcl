mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

variables {
  agent            = { create = false }
  kubernetes_admin = { enabled = false }
  agent_id         = "agent-existing"
  helm             = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

# The caller stores token and gateway separately; the module assembles HOOP_KEY.
run "agent_key_uses_default_gateway" {
  command = plan

  variables {
    agent_key = { name = "acme", token = "tok-123" }
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[1]).config.HOOP_KEY == "grpcs://acme:tok-123@hoop-grpc.ops.paragoninternal.com:8443?mode=standard"
    error_message = "agent_key must use the default gRPC gateway when no server is given."
  }
}

run "agent_key_parts_are_assembled" {
  command = plan

  variables {
    agent_key = {
      name   = "acme"
      token  = "tok-123"
      server = "hoop-grpc.example.test:8443"
    }
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[1]).config.HOOP_KEY == "grpcs://acme:tok-123@hoop-grpc.example.test:8443?mode=standard"
    error_message = "agent_key must be assembled into the standard-mode HOOP_KEY DSN."
  }
}

run "hoop_key_is_passed_through" {
  command = plan

  variables {
    hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[1]).config.HOOP_KEY == "grpcs://agent:placeholder@example.test?mode=standard"
    error_message = "hoop_key must reach the chart unchanged, as a sensitive value."
  }

  assert {
    condition     = !can(yamldecode(helm_release.agent.values[0]).config)
    error_message = "The key must never be set through a non-sensitive set block."
  }
}

run "key_is_required" {
  command = plan

  expect_failures = [helm_release.agent]
}

run "key_sources_are_exclusive" {
  command = plan

  variables {
    hoop_key  = "grpcs://agent:placeholder@example.test?mode=standard"
    agent_key = { name = "acme", token = "tok", server = "example.test:8443" }
  }

  expect_failures = [helm_release.agent]
}

# Workload identity differs per cloud, the module only forwards annotations.
run "aws_irsa_annotation" {
  command = plan

  variables {
    hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
    helm = {
      namespace        = "paragon"
      version          = "1.0.0"
      image_repository = "useparagon/hoop-agent-tools"
      image_tag        = "1.2.1"
      service_account = {
        annotations = { "eks.amazonaws.com/role-arn" = "arn:aws:iam::123456789012:role/hoop-support" }
      }
    }
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[0]).serviceAccount.annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/hoop-support"
    error_message = "The IRSA annotation must be rendered into the chart values."
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[0]).serviceAccount.create == true
    error_message = "The ServiceAccount is created by the chart by default."
  }
}

run "azure_and_gcp_annotations_and_extra_values" {
  command = plan

  variables {
    hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
    helm = {
      namespace        = "paragon"
      version          = "1.0.0"
      image_repository = "useparagon/hoop-agent-tools"
      image_tag        = "1.2.1"
      values           = ["replicaCount: 2"]
      service_account = {
        name = "hoop"
        annotations = {
          "azure.workload.identity/client-id" = "00000000-0000-0000-0000-000000000000"
          "iam.gke.io/gcp-service-account"    = "hoop@demo.iam.gserviceaccount.com"
        }
      }
    }
  }

  assert {
    condition     = yamldecode(helm_release.agent.values[0]).serviceAccount.name == "hoop" && length(yamldecode(helm_release.agent.values[0]).serviceAccount.annotations) == 2
    error_message = "ServiceAccount name and every annotation must be forwarded."
  }

  assert {
    condition     = length(helm_release.agent.values) == 3 && helm_release.agent.values[2] == "replicaCount: 2"
    error_message = "Caller values must follow the generated ServiceAccount values so they can override them."
  }
}

# One policy for the whole workspace instead of repeating it per connection.
run "defaults_policy" {
  command = plan

  variables {
    hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
    defaults = {
      access_control_groups    = ["only-admins"]
      postgres_guardrail_rules = ["pg-guardrail"]
      redis_guardrail_rules    = ["redis-guardrail"]
      tags                     = { cloud = "aws", environment = "prod" }
    }
    postgres = {
      main = { host = "db.test", user = "u", password = "p", database = "d" }
      own  = { host = "db2.test", user = "u", password = "p", database = "d", guardrail_rules = ["custom"], access_control_groups = ["only-me"], tags = { environment = "staging" } }
    }
    redis = {
      cache = { host = "redis.test" }
    }
    connections = {
      grafana = { type = "application", subtype = "tcp", tags = { "service-type" = "monitoring" } }
    }
  }

  assert {
    condition     = hoop_connection.postgres["postgres-main"].guardrail_rules == tolist(["pg-guardrail"]) && hoop_connection.postgres["postgres-own"].guardrail_rules == tolist(["custom"])
    error_message = "Default Postgres guardrails apply only when the entry sets none."
  }

  assert {
    condition     = hoop_connection.this["redis-cache"].guardrail_rules == tolist(["redis-guardrail"])
    error_message = "Default Redis guardrails apply to typed Redis connections."
  }

  assert {
    condition     = length(hoop_plugin_connection.access_control) == 4 && hoop_plugin_connection.access_control["postgres-own"].config == tolist(["only-me"]) && hoop_plugin_connection.access_control["grafana"].config == tolist(["only-admins"])
    error_message = "Default access groups must reach every connection without its own groups, and per-connection groups must win."
  }

  assert {
    condition     = hoop_connection.postgres["postgres-own"].tags["environment"] == "staging" && hoop_connection.postgres["postgres-main"].tags["environment"] == "prod" && hoop_connection.this["grafana"].tags["cloud"] == "aws" && hoop_connection.this["grafana"].tags["service-type"] == "monitoring"
    error_message = "Default tags are merged under connection tags, and connection tags win."
  }
}

run "connection_names_output" {
  command = plan

  variables {
    hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
    postgres = { main = { name = "acme-postgres-db", host = "db.test", user = "u", password = "p", database = "d" } }
    redis    = { cache = { host = "redis.test" } }
  }

  assert {
    condition     = output.connection_names["postgres-main"] == "acme-postgres-db" && output.connection_names["redis-cache"] == "redis-cache"
    error_message = "connection_names must expose the effective Hoop name for every key."
  }
}
