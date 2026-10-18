mock_provider "hoop" {}
mock_provider "helm" {}

variables {
  hoop_key = "grpcs://agent:placeholder@example.test?mode=standard"
  helm     = { namespace = "paragon", version = "1.0.0", image_repository = "useparagon/hoop-agent-tools", image_tag = "1.2.1" }
}

# Same module, different caller-computed connection maps. No cloud selector.
run "enterprise_multi_cloud_values" {
  command = plan

  variables {
    agent_id = "agent-existing"
    connections = {
      postgres_hermes = {
        name                  = "hermes-db"
        type                  = "database"
        subtype               = "postgres"
        access_mode_connect   = "enabled"
        access_schema         = "enabled"
        access_control_groups = ["platform-team"]
        guardrail_rules       = ["postgres-guardrail"]
        reviewers             = ["db-reviewers"]
        secrets = {
          "envvar:HOST"    = "db.example.test"
          "envvar:PORT"    = "5432"
          "envvar:USER"    = "reader"
          "envvar:PASS"    = "test-placeholder"
          "envvar:DB"      = "hermes"
          "envvar:SSLMODE" = "require"
        }
      }
      redis_azure_managed = {
        name                  = "managed-cache"
        type                  = "custom"
        subtype               = "redis"
        command               = ["redis-cli", "-c", "--tls", "--cacert", "$REDIS_CACERT_PATH"]
        access_control_groups = ["platform-team"]
        secrets = {
          "envvar:HOST"                  = "managed.example.test"
          "envvar:PORT"                  = "10000"
          "envvar:REDISCLI_AUTH"         = "test-placeholder"
          "filesystem:REDIS_CACERT_PATH" = "test-certificate-placeholder"
        }
      }
      kubernetes_gcp = {
        name                  = "k8s-admin"
        type                  = "custom"
        command               = ["bash"]
        access_mode_connect   = "enabled"
        access_control_groups = ["platform-team"]
        secrets = {
          "envvar:REMOTE_URL"            = "https://kubernetes.default.svc.cluster.local"
          "envvar:HEADER_AUTHORIZATION"  = "Bearer test-token"
          "envvar:CLOUDSDK_CORE_PROJECT" = "demo-project"
        }
      }
    }
  }

  assert {
    condition     = length(hoop_connection.postgres) == 1 && length(hoop_connection.this) == 2
    error_message = "Enterprise maps must create exactly the supplied connections, regardless of source cloud."
  }

  assert {
    condition     = length(hoop_plugin_connection.access_control) == 3
    error_message = "Explicit per-connection access groups must attach to all three connections."
  }


  assert {
    condition     = hoop_connection.this["redis_azure_managed"].subtype == "redis"
    error_message = "The caller-provided Redis subtype must be retained."
  }
}

run "managed_sync_and_agent_os" {
  command = plan

  variables {
    agent_id = "kubernetes-agent"
    postgres = {
      managed_sync = {
        name                  = "managed-sync-db"
        host                  = "postgres.service.local"
        user                  = "reader"
        password              = "placeholder"
        database              = "managed_sync"
        access_control_groups = ["operations"]
      }
      agent_os = {
        host     = "agent-os.postgres.local"
        user     = "agent"
        password = "placeholder"
        database = "agent_os"
      }
    }
    redis = {
      agent_os = {
        name                  = "agent-os-redis"
        host                  = "redis.service.local"
        ssl                   = true
        ca_certificate        = "placeholder-ca"
        password              = "placeholder"
        access_control_groups = ["operations"]
      }
    }
    connections = {
      cluster_admin = {
        type    = "custom"
        command = ["bash"]
        secrets = {
          "envvar:REMOTE_URL" = "https://kubernetes.default.svc.cluster.local"
        }
      }
    }
  }

  assert {
    condition     = length(hoop_connection.postgres) == 2 && length(hoop_connection.this) == 2
    error_message = "Managed Sync and Agent OS must share generic Postgres/Redis mapping without dedicated environment modules."
  }

  assert {
    condition     = hoop_connection.postgres["postgres-managed_sync"].secrets["envvar:PORT"] == "5432" && hoop_connection.postgres["postgres-managed_sync"].access_schema == "enabled"
    error_message = "PostgreSQL defaults and native secret mapping should be applied."
  }

  assert {
    condition     = contains(hoop_connection.this["redis-agent_os"].command, "--tls") && contains(hoop_connection.this["redis-agent_os"].command, "--cacert")
    error_message = "Redis TLS and CA options must be reflected in CLI command."
  }

  assert {
    condition     = hoop_connection.this["redis-agent_os"].secrets["filesystem:REDIS_CACERT_PATH"] == "placeholder-ca"
    error_message = "Redis CA certificate must be provided in the compatible Hoop filesystem secret."
  }

  assert {
    condition     = length(hoop_plugin_connection.access_control) == 2
    error_message = "Access control association must work for typed connections."
  }
}

run "redis_custom_command" {
  command = plan

  variables {
    agent_id = "kubernetes-agent"
    redis = {
      managed = {
        host    = "managed.redis.local"
        command = ["redis-cli", "--tls", "-h", "$HOST", "-p", "$PORT"]
        extra_secrets = {
          "envvar:EXTRA_OPTION" = "custom"
        }
      }
    }
  }

  assert {
    condition     = hoop_connection.this["redis-managed"].command == tolist(["redis-cli", "--tls", "-h", "$HOST", "-p", "$PORT"])
    error_message = "Redis caller overrides must remain untouched."
  }

  assert {
    condition     = hoop_connection.this["redis-managed"].secrets["envvar:EXTRA_OPTION"] == "custom" && hoop_connection.this["redis-managed"].secrets["envvar:HOST"] == "managed.redis.local"
    error_message = "Custom Redis secret keys must be preserved without overriding the typed host."
  }
}

run "observability_values" {
  command = plan

  variables {
    agent_id = "observability-agent"
    connections = {
      metrics = {
        name                  = "metrics"
        type                  = "application"
        subtype               = "tcp"
        command               = ["bash"]
        access_mode_connect   = "enabled"
        access_control_groups = ["operations"]
        tags                  = { "service-type" = "observability" }
        secrets               = { "envvar:HOST" = "metrics.example.test", "envvar:PORT" = "8428" }
      }
    }
  }

  assert {
    condition     = length(hoop_connection.this) == 1 && length(hoop_connection.postgres) == 0
    error_message = "Observability uses the same module without any Enterprise or Cloud-specific inputs."
  }

  assert {
    condition     = length(hoop_plugin_connection.access_control) == 1
    error_message = "Observability must preserve per-connection Access Control."
  }
}
