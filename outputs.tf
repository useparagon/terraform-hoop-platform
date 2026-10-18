output "agent_id" {
  description = "ID of the existing Hoop agent provided by the caller. Mirrors agent_id without creating or changing the agent."
  value       = var.agent_id
}

output "connection_ids" {
  description = "Map of connection IDs returned by Hoop, keyed by the same stable identifiers used in connections. Empty when no connections are configured; IDs become available after creation."
  value       = local.connection_ids
}
