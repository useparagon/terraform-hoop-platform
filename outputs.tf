output "agent_id" {
  description = "ID of the Hoop agent. The ID returned by the registration when agent.create is true, or the agent_id supplied by the caller when agent.create is false."
  value       = local.agent_id
}

output "connection_ids" {
  description = "Map of connection IDs returned by Hoop, keyed by the same stable identifiers used in connections. Empty when no connections are configured; IDs become available after creation."
  value       = local.connection_ids
}

output "connection_names" {
  description = "Map of Hoop connection names, keyed by the same stable identifiers used in connections, postgres (postgres-<key>) and redis (redis-<key>)."
  value       = { for key, conn in local.all_connections : key => nonsensitive(coalesce(conn.name, key)) }
}

output "helm_release" {
  description = "Deployed agent release: name, namespace, chart version and status. Lets callers order dependent resources after the agent."
  value = {
    name      = helm_release.agent.name
    namespace = helm_release.agent.namespace
    version   = helm_release.agent.version
    status    = helm_release.agent.status
  }
}
