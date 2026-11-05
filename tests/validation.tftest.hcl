mock_provider "hoop" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "terracurl" {}
mock_provider "http" {}
mock_provider "time" {}

variables {
  agent            = { create = false }
  kubernetes_admin = { enabled = false }
  hoop_key         = "grpcs://agent:placeholder@example.test?mode=standard"
  helm             = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

run "invalid_agent_id" {
  command = plan

  variables {
    agent_id = "  "
  }

  expect_failures = [var.agent_id]
}

run "unsupported_connection_type" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      invalid = { type = "unsupported" }
    }
  }

  expect_failures = [var.connections]
}

run "invalid_access_mode" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      invalid = {
        type                = "application"
        access_mode_connect = "maybe"
      }
    }
  }

  expect_failures = [var.connections]
}

run "duplicate_connection_key" {
  command = plan
  variables {
    agent_id = "agent-existing"
    postgres = {
      main = { host = "postgres.local", user = "reader", password = "placeholder", database = "app" }
    }
    connections = {
      "postgres-main" = { type = "custom" }
    }
  }
  expect_failures = [hoop_connection.postgres]
}

run "redis_reserved_host_is_rejected" {
  command = plan

  variables {
    agent_id = "agent-existing"
    redis = {
      primary = {
        host = "correct.redis.local"
        extra_secrets = {
          "envvar:HOST" = "wrong.redis.local"
        }
      }
    }
  }

  expect_failures = [var.redis]
}

run "redis_reserved_auth_is_rejected" {
  command = plan

  variables {
    agent_id = "agent-existing"
    redis = {
      primary = {
        host     = "redis.local"
        password = "correct-password"
        extra_secrets = {
          "envvar:REDISCLI_AUTH" = "wrong-password"
        }
      }
    }
  }

  expect_failures = [var.redis]
}

run "duplicate_connection_names_across_maps" {
  command = plan

  variables {
    agent_id = "agent-existing"
    postgres = {
      primary = {
        name     = "shared-name"
        host     = "postgres.local"
        user     = "reader"
        password = "placeholder"
        database = "app"
      }
    }
    connections = {
      application = {
        name = "shared-name"
        type = "custom"
      }
    }
  }

  expect_failures = [hoop_connection.this, hoop_connection.postgres]
}

run "duplicate_connection_names_in_custom_map" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      first = {
        name = "duplicate"
        type = "custom"
      }
      second = {
        name = "duplicate"
        type = "custom"
      }
    }
  }

  expect_failures = [hoop_connection.this]
}

run "invalid_helm_timeout" {
  command = plan

  variables {
    agent_id = "agent-existing"
    helm = {
      namespace        = "paragon"
      version          = "1.0.0"
      image_repository = "useparagon/hoop-agent-tools"
      image_tag        = "1.2.1"
      timeout          = 0
    }
  }

  expect_failures = [var.helm]
}
