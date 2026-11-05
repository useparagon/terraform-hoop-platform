# terraform-hoop-platform

A reusable Terraform module that deploys a Hoop agent on Kubernetes and manages its connections. It works the same on AWS (EKS), Azure (AKS) and GCP (GKE); the only cloud-specific input is the workload-identity annotation.

It does four things:

1. Registers the agent in Hoop, or adopts one that already exists.
2. Installs the agent with Helm.
3. Creates the ServiceAccount, the ClusterRoleBinding and the token behind the `k8s-admin` connection.
4. Creates the Hoop connections (Postgres, Redis, applications, kubectl) with their access control.

The module is cloud-agnostic. Everything cloud-specific (the IAM role, Azure identity or GCP service account, and their trust) stays in the caller and reaches the agent as a ServiceAccount annotation. Slack integration is out of scope and is managed separately.

```hcl
module "hoop" {
  source     = "git::https://github.com/useparagon/terraform-hoop-platform.git?ref=v1.0.0"
  agent_name = "example-agent"

  agent = {
    api_key = var.hoop_api_key # TF_VAR_hoop_api_key, never a tfvars file
  }

  helm = {
    namespace = "paragon"
    service_account = {
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.hoop_support.arn }
    }
  }

  kubernetes_admin = {
    extra_secrets = local.irsa_env # envvar:AWS_ROLE_ARN, so kubectl sessions assume the support role
  }

  defaults = {
    tags = { environment = "staging", cloud = "aws" }
  }

  postgres = local.hoop_postgres
  redis    = local.hoop_redis
}
```

Always pin `?ref=` to a released tag. Never use a branch. The runner that executes Terraform needs read access to this repository.

## What changes between callers

Nothing in the module. Only the values:

| | AWS | Azure / GCP |
| --- | --- | --- |
| Agent | `agent.create = true` (the default) | Same. `create = false` plus `agent_id` and `hoop_key` only for agents that already exist, because Hoop issued their key once and will not return it again |
| Identity annotation | `eks.amazonaws.com/role-arn` | `azure.workload.identity/client-id` (AKS) or `iam.gke.io/gcp-service-account` (GKE) |
| Namespace | any existing namespace (`helm.namespace`) | any existing namespace (`helm.namespace`) |
| Access policy | `defaults.access_control_groups` | the same input, computed from `customer_facing` |

## Behavior worth knowing

- **Agent.** `agent.create = true` registers the agent through the Hoop API and removes it on destroy. Creation accepts only HTTP 201: a 409 means the agent already exists and its one-time key cannot be recovered, so the run fails on purpose. `agent.create = false` never calls the API. The resource can be imported, but the import cannot recover that key, so an existing agent is adopted with `create = false` and its current key. Only `hpk_` API keys are supported (`Authorization: Bearer`).
- **Key.** With `agent.create = true` the key comes from the registration. Otherwise set exactly one of `hoop_key` (complete `grpcs://` DSN) or `agent_key` (name, token, server; the module assembles the DSN). It reaches Helm only through `set_sensitive`. This is not the Hoop provider API key; configure the provider with `HOOP_APIKEY` and `HOOP_APIURL` in the root workspace.
- **kubectl connection.** Set `kubernetes_admin` to create it; leave it unset to skip it. The ClusterRoleBinding is cluster-scoped, so set `resource_suffix` when several agents share one cluster. Default object names (`hoop-cluster-admin`, `hoop-cluster-admin-token`) match what is deployed today. The plan fails if the token is empty instead of storing `Bearer `.
- **Defaults.** `defaults` is the single place for the access policy: groups, guardrails and tags apply to every connection that does not set its own value, and connection-level values always win.
- **Keys and names.** Postgres entries become `postgres-<key>`, Redis entries `redis-<key>`, the kubectl connection is `k8s-admin`, and `connections` keys stay as given. Duplicate keys or final connection names fail the plan. Map keys, names, types and group names must not be secret.
- **Redis.** The default command adds `--tls` when `ssl = true` and mounts `ca_certificate` as a file. Authentication goes through `REDISCLI_AUTH`. `extra_secrets` adds keys but cannot override HOST, PORT, DB_NUMBER, REDISCLI_AUTH or REDIS_CACERT_PATH.
- **Postgres.** `sslmode` defaults to `require`. The provider normalizes the Postgres command, so that resource ignores `command` changes.
- **State.** The API key, connection passwords and certificates can end up in Terraform state. Use encrypted, access-restricted remote state.

## Migrating an existing Hoop workspace

Moving resources keeps the live agent and avoids a reinstall. For an agent that already exists, set `agent.create = false` and keep the current `agent_id` and key, then add `moved` blocks for the single-instance resources:

```hcl
moved {
  from = module.hoop_old.helm_release.hoopagent[0]
  to   = module.hoop.helm_release.agent
}

moved {
  from = kubernetes_service_account.hoop_cluster_admin[0]
  to   = module.hoop.kubernetes_service_account.admin[0]
}

moved {
  from = kubernetes_cluster_role_binding.hoop_cluster_admin[0]
  to   = module.hoop.kubernetes_cluster_role_binding.admin[0]
}

moved {
  from = kubernetes_secret.hoop_cluster_admin_token[0]
  to   = module.hoop.kubernetes_secret.admin_token[0]
}
```

Connections are recreated, not moved: the new module creates them under new Terraform addresses and destroys the old ones in the same plan, so connections are briefly unavailable. An apply can hit a "name already exists" error because create and delete run in parallel; one retry after the old connection is gone resolves it. Check the plan before applying: the old in-tree modules also owned cloud IAM, which this module deliberately does not. Slack configuration is not touched by this module.

## Development

```sh
terraform fmt -recursive
terraform init -backend=false
terraform test
terraform-docs markdown table --hide providers --indent 2 --output-mode inject --output-file README.md .
# Use terraform-docs v0.20.0, the version the validate workflow runs; other versions format tables differently.
```

Workflows live in `.whiskers` and the YAML under `.github/workflows` is generated. After changing a workflow, regenerate it:

```sh
yarn ci:compile   # writes .github/workflows/*.yaml
yarn ci:verify    # fails when the YAML drifts from the Whiskers sources
```

Releases are manual: run the `release` workflow on `main`. The version comes from the commits since the last tag, the same rules `agent-os` uses: `feat` bumps the minor, `fix` bumps the patch, and a breaking change (`feat!:` or a `BREAKING CHANGE:` footer) bumps the major. Commits that change nothing releasable (`chore`, `docs`, `ci`) produce no tag. The first release, with no tag yet, becomes `v0.1.0`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.0.0, < 3.0.0 |
| <a name="requirement_hoop"></a> [hoop](#requirement\_hoop) | >= 0.0.21, < 0.1.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.20.0, < 3.0.0 |
| <a name="requirement_terracurl"></a> [terracurl](#requirement\_terracurl) | >= 2.11.0, < 3.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [hoop_connection.postgres](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/connection) | resource |
| [hoop_connection.this](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/connection) | resource |
| [hoop_plugin_connection.access_control](https://registry.terraform.io/providers/hoophq/hoop/latest/docs/resources/plugin_connection) | resource |
| [kubernetes_cluster_role_binding.admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_secret.admin_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service_account.admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |
| [terracurl_request.agent](https://registry.terraform.io/providers/devops-rob/terracurl/latest/docs/resources/request) | resource |
| [time_sleep.admin_token](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [http_http.agent](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |
| [kubernetes_secret.admin_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent"></a> [agent](#input\_agent) | Agent registration in the Hoop platform. The same for every caller.<br/><br/>create = true (default): the module registers the agent through the Hoop API and removes it on destroy. api\_key is required; api\_url defaults to Paragon's Hoop API. agent\_id and agent\_key come from the registration.<br/>create = false: the agent already exists and Hoop will not issue its key again. The module does not call the API, and the caller supplies agent\_id and agent\_key (or hoop\_key). | <pre>object({<br/>    create  = optional(bool, true)<br/>    api_url = optional(string, "https://hoop.ops.paragoninternal.com/api")<br/>    api_key = optional(string)<br/>    mode    = optional(string, "standard")<br/>  })</pre> | `{}` | no |
| <a name="input_agent_id"></a> [agent\_id](#input\_agent\_id) | ID of an agent that already exists in Hoop. Required when agent.create is false; ignored when the module registers the agent. | `string` | `null` | no |
| <a name="input_agent_key"></a> [agent\_key](#input\_agent\_key) | Agent key as separate parts. The module assembles grpcs://<name>:<token>@<server>?mode=<mode>. Use it when the token and the gateway address come from different sources. server defaults to grpc\_server. Set exactly one of hoop\_key or agent\_key when agent.create is false. | <pre>object({<br/>    name   = string<br/>    token  = string<br/>    server = optional(string)<br/>    mode   = optional(string, "standard")<br/>  })</pre> | `null` | no |
| <a name="input_agent_name"></a> [agent\_name](#input\_agent\_name) | Name of the Hoop agent. It becomes part of the HOOP\_KEY, so use a stable, environment-identifying name (for example example-agent). Required when the module registers the agent (agent.create = true). | `string` | `null` | no |
| <a name="input_connections"></a> [connections](#input\_connections) | Optional advanced Hoop connections, keyed by stable, non-secret Terraform identifiers. Defaults to an empty map (no connections). For ordinary PostgreSQL and Redis use postgres and redis inputs instead. The consuming workspace prepares every entry using its own Terraform locals, configuration and secret sources; this module does not need to know the cloud.<br/><br/>Required field per entry: type (database, application or custom).<br/>Optional fields: name (defaults to the map key), subtype (e.g. postgres, redis or tcp), jira\_issue\_template\_id (Hoop approval ticket template), command (argument list), secrets (Hoop-compatible envvar:/filesystem: values), tags, guardrail\_rules, reviewers and access\_control\_groups.<br/><br/>Access modes accept "enabled" or "disabled"; runbooks and exec default to "enabled", while connect and schema default to "disabled". Lists and maps default to empty. PostgreSQL database connections use a separate resource to ignore provider command normalization.<br/><br/>The map itself is not marked sensitive so plans can display non-secret connection metadata. The Hoop provider marks secrets as sensitive; credentials may nevertheless remain in Terraform state. Inputs derived from an entirely sensitive source may still hide other fields in plans. Never use secrets as map keys, names, types, reviewers or access group names. | <pre>map(object({<br/>    name                   = optional(string)<br/>    type                   = string<br/>    subtype                = optional(string)<br/>    jira_issue_template_id = optional(string)<br/>    command                = optional(list(string))<br/>    secrets                = optional(map(string), {})<br/>    tags                   = optional(map(string), {})<br/>    guardrail_rules        = optional(list(string), [])<br/>    reviewers              = optional(list(string), [])<br/>    access_control_groups  = optional(list(string), [])<br/><br/>    access_mode_runbooks = optional(string, "enabled")<br/>    access_mode_exec     = optional(string, "enabled")<br/>    access_mode_connect  = optional(string, "disabled")<br/>    access_schema        = optional(string, "disabled")<br/>  }))</pre> | `{}` | no |
| <a name="input_defaults"></a> [defaults](#input\_defaults) | Policy applied to every connection that does not set its own value, so each caller states its access policy once instead of repeating it per connection.<br/><br/>access\_control\_groups: groups attached to connections whose access\_control\_groups is empty. Defaults to the groups used across deployments (dev-team-oncall, dev-team-managers, admin).<br/>postgres\_guardrail\_rules / redis\_guardrail\_rules: guardrails for the typed postgres / redis inputs when the entry sets none. Defaults to the shared guardrail rule IDs.<br/>tags: merged under each connection's own tags (connection tags win). | <pre>object({<br/>    access_control_groups    = optional(list(string), ["dev-team-oncall", "dev-team-managers", "admin"])<br/>    postgres_guardrail_rules = optional(list(string), ["a85115f6-5ef3-4618-b70c-f7cccdc62c5a"])<br/>    redis_guardrail_rules    = optional(list(string), ["182f59b2-5d5d-4ab8-978e-94472b3915fc"])<br/>    tags                     = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_grpc_server"></a> [grpc\_server](#input\_grpc\_server) | Hoop gRPC gateway address (host:port) used when the module assembles the HOOP\_KEY. Null uses Paragon's gateway. | `string` | `null` | no |
| <a name="input_helm"></a> [helm](#input\_helm) | Helm release configuration. Set namespace, chart version, and the Paragon-built agent image repository (including its registry when needed) and immutable image tag explicitly. The chart version and agent image tag are independent. service\_account carries cloud workload-identity annotations (eks.amazonaws.com/role-arn, azure.workload.identity/client-id, iam.gke.io/gcp-service-account); values adds any further chart values. | <pre>object({<br/>    namespace        = string<br/>    version          = optional(string, "1.184.2")<br/>    image_repository = optional(string, "useparagon/hoop-agent-tools")<br/>    image_tag        = optional(string, "1.2.1")<br/>    name             = optional(string, "hoopagent")<br/>    create_namespace = optional(bool, false)<br/>    values           = optional(list(string), [])<br/>    timeout          = optional(number, 300)<br/>    service_account = optional(object({<br/>      create      = optional(bool, true)<br/>      name        = optional(string)<br/>      annotations = optional(map(string), {})<br/>    }), {})<br/>  })</pre> | n/a | yes |
| <a name="input_hoop_key"></a> [hoop\_key](#input\_hoop\_key) | Complete agent HOOP\_KEY value, such as grpcs://agent-name:token@gateway.example.com?mode=standard. Set exactly one of hoop\_key or agent\_key. This is NOT the Hoop provider API key. | `string` | `null` | no |
| <a name="input_kubernetes_admin"></a> [kubernetes\_admin](#input\_kubernetes\_admin) | kubectl connection backed by a ServiceAccount, a ClusterRoleBinding and a token Secret. null disables it.<br/><br/>The ClusterRoleBinding is cluster-scoped, so set resource\_suffix when several agents share one cluster. extra\_secrets adds connection secrets beyond the token, such as the IRSA environment variables a kubectl session needs to assume the support role. | <pre>object({<br/>    enabled               = optional(bool, true)<br/>    service_account_name  = optional(string, "hoop-cluster-admin")<br/>    token_secret_name     = optional(string, "hoop-cluster-admin-token")<br/>    cluster_role          = optional(string, "cluster-admin")<br/>    resource_suffix       = optional(string, "")<br/>    token_wait_duration   = optional(string, "10s")<br/>    name                  = optional(string)<br/>    remote_url            = optional(string, "https://kubernetes.default.svc.cluster.local")<br/>    insecure              = optional(bool, true)<br/>    kubectl_namespace     = optional(string)<br/>    extra_secrets         = optional(map(string), {})<br/>    tags                  = optional(map(string), {})<br/>    guardrail_rules       = optional(list(string), [])<br/>    reviewers             = optional(list(string), [])<br/>    access_control_groups = optional(list(string), [])<br/>    access_mode_runbooks  = optional(string, "enabled")<br/>    access_mode_exec      = optional(string, "enabled")<br/>    access_mode_connect   = optional(string, "enabled")<br/>  })</pre> | `null` | no |
| <a name="input_postgres"></a> [postgres](#input\_postgres) | PostgreSQL connections keyed by stable names. Credentials and endpoints come from the Kubernetes caller's existing Terraform secret source. Each entry accepts host, port (default 5432), user, password, database, sslmode, tags, guardrails, reviewers and access groups. | <pre>map(object({<br/>    name                  = optional(string)<br/>    host                  = string<br/>    port                  = optional(number, 5432)<br/>    user                  = string<br/>    password              = string<br/>    database              = string<br/>    sslmode               = optional(string, "require")<br/>    tags                  = optional(map(string), {})<br/>    guardrail_rules       = optional(list(string), [])<br/>    reviewers             = optional(list(string), [])<br/>    access_control_groups = optional(list(string), [])<br/>    access_mode_connect   = optional(string, "disabled")<br/>    access_schema         = optional(string, "enabled")<br/>  }))</pre> | `{}` | no |
| <a name="input_redis"></a> [redis](#input\_redis) | Redis connections keyed by stable names. Each entry specifies host, port (default 6379), DB index, TLS/CA options and optional authentication. Override the CLI command when necessary; extra\_secrets can add environment-specific keys but cannot override HOST, PORT, DB\_NUMBER, REDISCLI\_AUTH, or REDIS\_CACERT\_PATH. No cloud-specific logic is embedded in the module. | <pre>map(object({<br/>    name                  = optional(string)<br/>    host                  = string<br/>    port                  = optional(number, 6379)<br/>    db_number             = optional(number, 0)<br/>    password              = optional(string)<br/>    ssl                   = optional(bool, false)<br/>    ca_certificate        = optional(string)<br/>    command               = optional(list(string))<br/>    extra_secrets         = optional(map(string), {})<br/>    tags                  = optional(map(string), {})<br/>    guardrail_rules       = optional(list(string), [])<br/>    reviewers             = optional(list(string), [])<br/>    access_control_groups = optional(list(string), [])<br/>    access_mode_connect   = optional(string, "disabled")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_id"></a> [agent\_id](#output\_agent\_id) | ID of the Hoop agent. The ID returned by the registration when agent.create is true, or the agent\_id supplied by the caller when agent.create is false. |
| <a name="output_connection_ids"></a> [connection\_ids](#output\_connection\_ids) | Map of connection IDs returned by Hoop, keyed by the same stable identifiers used in connections. Empty when no connections are configured; IDs become available after creation. |
| <a name="output_connection_names"></a> [connection\_names](#output\_connection\_names) | Map of Hoop connection names, keyed by the same stable identifiers used in connections, postgres (postgres-<key>) and redis (redis-<key>). |
| <a name="output_helm_release"></a> [helm\_release](#output\_helm\_release) | Deployed agent release: name, namespace, chart version and status. Lets callers order dependent resources after the agent. |
<!-- END_TF_DOCS -->
