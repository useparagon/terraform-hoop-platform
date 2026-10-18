# Terraform Hoop Connections

Reusable Hoop **connection** module for Kubernetes deployments: Enterprise (AWS, Azure, GCP), Observability, Managed Sync, Agent OS and future Kubernetes services. Cloud ECS is **not a consumer**; its existing Hoop integration and agent runtime stay in Cloud.

The module deploys the Kubernetes Hoop agent using Helm and registers database, Redis, Kubernetes and application connections against an **existing Hoop agent ID**. The agent can be reinstalled without changing its Hoop ID. Consumers provide the complete sensitive `HOOP_KEY`, configure the Hoop provider via `HOOP_APIKEY`/`HOOP_APIURL` in their root workspace, and own identity, cloud secrets, Kubernetes RBAC and networking. **Slack is entirely out of scope** and is owned by Ops. When migrating from existing Hoop workspaces, preserve or re-establish any required per-connection Slack approval notifications separately: retiring the old Slack associations without replacing them removes approval notifications. The global Slack plugin must have one Ops owner and must not be destroyed accidentally.

## Usage

```hcl
module "hoop_platform" {
  source   = "git::https://github.com/OWNER/terraform-hoop-platform.git?ref=v0.0.1"
  agent_id = var.hoop_agent_id
  hoop_key = local.hoop_key
  helm = {
    namespace        = "paragon"
    version          = var.hoop_version # Helm chart version, independent of image tag
    image_repository = var.hoop_image_repository # e.g. useparagon/hoop-agent-tools on Docker Hub
    image_tag        = var.hoop_image_tag        # e.g. 1.2.1; pin a released tag
    values           = [yamlencode({ serviceAccount = { annotations = local.hoop_service_account_annotations } })]
  }

  postgres = {
    managed_sync = {
      host     = local.managed_sync_postgres.host
      user     = local.managed_sync_postgres.user
      password = local.managed_sync_postgres.password
      database = local.managed_sync_postgres.database
    }
    agent_os = {
      host     = local.agent_os_postgres.host
      user     = local.agent_os_postgres.user
      password = local.agent_os_postgres.password
      database = local.agent_os_postgres.database
    }
  }

  redis = {
    agent_os = {
      host           = local.agent_os_redis.host
      ssl            = true
      password       = local.agent_os_redis.password
      ca_certificate = local.agent_os_redis.ca_certificate
    }
  }

  connections = {
    kubernetes = {
      type    = "custom"
      command = ["bash"]
      secrets = local.hoop_kubernetes_secrets
    }
  }
}
```

## Replacing an existing deployment

Replace the old Terraform module declaration and introduce this module under a **different Terraform block name**, such as `module "hoop_platform"`, **in the same configuration change**. For example, remove `module "hoop" { source = "./hoop" ... }` from the Enterprise or Observability caller, then add `module "hoop_platform"` using the source and inputs shown above. Terraform will plan the deletion of the old module's resources and creation of the new module's resources in the same apply. There is **no separate manual destroy, no `moved` blocks, imports, `terraform state mv`, or state surgery**. Reuse the same independently registered Hoop `agent_id`, agent name and `HOOP_KEY`; the remote Hoop agent registration is not managed by either Helm release. An interruption while runtime and connections are recreated is acceptable.

**Check the plan before applying:** the old in-tree Hoop modules also manage IAM/workload identity, Kubernetes RBAC, ServiceAccounts, tokens and (in Observability) a namespace; this shared module manages only the Helm runtime and Hoop connections. Any identity, RBAC or namespace still needed must remain or be declared in the consuming workspace. Slack configuration and approval notifications are separately owned by Ops.

**Same-name Helm releases:** a different Terraform module block name changes the resource address, **not** the actual Helm release name (`hoopagent`). Since the old and new release can have the same name and namespace, Terraform does **not guarantee** that the old release will be uninstalled before the new installation starts: independent operations can run concurrently. The one-plan replacement is the intended workflow, but an apply may encounter a Helm name-already-in-use conflict and need a retry after the old release is gone. Do not use Helm's unsafe `replace` option as a workaround. No consuming workspace has been modified here.

The image must be supplied explicitly: Enterprise and Observability currently default to Docker Hub `useparagon/hoop-agent-tools:1.2.1`, built in the `hoop-agent-tools` repository. Use `docker.io/useparagon/hoop-agent-tools` or the existing short Docker Hub repository name in `helm.image_repository`, and supply the deployed image tag separately in `helm.image_tag`. To use another registry, pass its full image repository address; ensure the cluster has appropriate pull access. Helm sets override conflicting image values in `helm.values`, so the chart cannot silently revert to the upstream image. The Helm **chart version** (`helm.version`) and **agent image tag** (`helm.image_tag`) are independent.

The example locals are **caller-defined**, and the URL is a placeholder until a real repository and tag exist. The `HOOP_KEY` in this example must be a complete `grpcs://` URL including agent name, token and server. Credentials can appear in Terraform state; use restricted encrypted state. Helm provider and Hoop provider configuration stay with the root workspace. Set only the connections required by that workspace. PostgreSQL keys are prefixed `postgres-`, Redis keys `redis-`, and advanced `connections` keys are unchanged; all keys must be unique. Any duplicate connection key fails the plan explicitly; no silent replacement is allowed.

Redis `extra_secrets` only adds additional keys. It cannot redefine `envvar:HOST`, `envvar:PORT`, `envvar:DB_NUMBER`, `envvar:REDISCLI_AUTH`, or `filesystem:REDIS_CACERT_PATH`; duplicate reserved keys fail input validation. Terraform also fails the plan for duplicate connection resource keys or final Hoop connection names, regardless of whether callers read module outputs. Helm `timeout` must be positive and defaults to 300 seconds.

For Redis, the default command enables `--tls` when `ssl = true` and mounts a provided CA certificate. Callers may override `command` and use `extra_secrets` for environment-specific Redis authentication (including Azure Managed Redis). PostgreSQL uses `SSLMODE = "require"` by default; set it explicitly if existing deployments differ. The caller supplies Kubernetes identity, tokens and cloud-specific secrets; the module does **not** read them from ESO or Kubernetes.

Terraform can store the Hoop key, connection passwords and certificates in **state**; use encrypted remote state and restricted access. Per-connection Access Control remains supported. **Slack resources, channels and configuration are excluded entirely.**

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.0.0, < 3.0.0 |
| <a name="requirement_hoop"></a> [hoop](#requirement\_hoop) | >= 0.0.21, < 0.1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.17.0 |
| <a name="provider_hoop"></a> [hoop](#provider\_hoop) | 0.0.22 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [hoop_connection.postgres](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/connection) | resource |
| [hoop_connection.this](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/connection) | resource |
| [hoop_plugin_connection.access_control](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/plugin_connection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agent_id"></a> [agent\_id](#input\_agent\_id) | ID of an existing Hoop agent registration in the Hoop platform. The module installs its Kubernetes runtime via Helm but does not create or change the platform agent registration. | `string` | n/a | yes |
| <a name="input_connections"></a> [connections](#input\_connections) | Optional advanced Hoop connections, keyed by stable, non-secret Terraform identifiers. Defaults to an empty map (no connections). For ordinary PostgreSQL and Redis use postgres and redis inputs instead. The consuming workspace prepares every entry using its own Terraform locals, configuration and secret sources; this module does not need to know the cloud.<br/><br/>Required field per entry: type (database, application or custom).<br/>Optional fields: name (defaults to the map key), subtype (e.g. postgres, redis or tcp), jira\_issue\_template\_id (Hoop approval ticket template), command (argument list), secrets (Hoop-compatible envvar:/filesystem: values), tags, guardrail\_rules, reviewers and access\_control\_groups.<br/><br/>Access modes accept "enabled" or "disabled"; runbooks and exec default to "enabled", while connect and schema default to "disabled". Lists and maps default to empty. PostgreSQL database connections use a separate resource to ignore provider command normalization.<br/><br/>The map itself is not marked sensitive so plans can display non-secret connection metadata. The Hoop provider marks secrets as sensitive; credentials may nevertheless remain in Terraform state. Inputs derived from an entirely sensitive source may still hide other fields in plans. Never use secrets as map keys, names, types, reviewers or access group names. | <pre>map(object({<br/>    name                   = optional(string)<br/>    type                   = string<br/>    subtype                = optional(string)<br/>    jira_issue_template_id = optional(string)<br/>    command                = optional(list(string))<br/>    secrets                = optional(map(string), {})<br/>    tags                   = optional(map(string), {})<br/>    guardrail_rules        = optional(list(string), [])<br/>    reviewers              = optional(list(string), [])<br/>    access_control_groups  = optional(list(string), [])<br/><br/>    access_mode_runbooks = optional(string, "enabled")<br/>    access_mode_exec     = optional(string, "enabled")<br/>    access_mode_connect  = optional(string, "disabled")<br/>    access_schema        = optional(string, "disabled")<br/>  }))</pre> | `{}` | no |
| <a name="input_helm"></a> [helm](#input\_helm) | Helm release configuration. Set namespace, chart version, and the Paragon-built agent image repository (including its registry when needed) and immutable image tag explicitly. The chart version and agent image tag are independent. Additional Helm values configure service accounts and cloud workload identities. | <pre>object({<br/>    namespace        = string<br/>    version          = string<br/>    image_repository = string<br/>    image_tag        = string<br/>    name             = optional(string, "hoopagent")<br/>    create_namespace = optional(bool, false)<br/>    values           = optional(list(string), [])<br/>    timeout          = optional(number, 300)<br/>  })</pre> | n/a | yes |
| <a name="input_hoop_key"></a> [hoop\_key](#input\_hoop\_key) | Complete agent HOOP\_KEY value, such as grpcs://agent-name:token@gateway.example.com?mode=standard. The caller constructs it using its existing secret source; this is NOT the Hoop provider API key. | `string` | n/a | yes |
| <a name="input_postgres"></a> [postgres](#input\_postgres) | PostgreSQL connections keyed by stable names. Credentials and endpoints come from the Kubernetes caller's existing Terraform secret source. Each entry accepts host, port (default 5432), user, password, database, sslmode, tags, guardrails, reviewers and access groups. | <pre>map(object({<br/>    name                  = optional(string)<br/>    host                  = string<br/>    port                  = optional(number, 5432)<br/>    user                  = string<br/>    password              = string<br/>    database              = string<br/>    sslmode               = optional(string, "require")<br/>    tags                  = optional(map(string), {})<br/>    guardrail_rules       = optional(list(string), [])<br/>    reviewers             = optional(list(string), [])<br/>    access_control_groups = optional(list(string), [])<br/>    access_mode_connect   = optional(string, "disabled")<br/>    access_schema         = optional(string, "enabled")<br/>  }))</pre> | `{}` | no |
| <a name="input_redis"></a> [redis](#input\_redis) | Redis connections keyed by stable names. Each entry specifies host, port (default 6379), DB index, TLS/CA options and optional authentication. Override the CLI command when necessary; extra\_secrets can add environment-specific keys but cannot override HOST, PORT, DB\_NUMBER, REDISCLI\_AUTH, or REDIS\_CACERT\_PATH. No cloud-specific logic is embedded in the module. | <pre>map(object({<br/>    name                  = optional(string)<br/>    host                  = string<br/>    port                  = optional(number, 6379)<br/>    db_number             = optional(number, 0)<br/>    password              = optional(string)<br/>    ssl                   = optional(bool, false)<br/>    ca_certificate        = optional(string)<br/>    command               = optional(list(string))<br/>    extra_secrets         = optional(map(string), {})<br/>    tags                  = optional(map(string), {})<br/>    guardrail_rules       = optional(list(string), [])<br/>    reviewers             = optional(list(string), [])<br/>    access_control_groups = optional(list(string), [])<br/>    access_mode_connect   = optional(string, "disabled")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_agent_id"></a> [agent\_id](#output\_agent\_id) | ID of the existing Hoop agent provided by the caller. Mirrors agent\_id without creating or changing the agent. |
| <a name="output_connection_ids"></a> [connection\_ids](#output\_connection\_ids) | Map of connection IDs returned by Hoop, keyed by the same stable identifiers used in connections. Empty when no connections are configured; IDs become available after creation. |
<!-- END_TF_DOCS -->
