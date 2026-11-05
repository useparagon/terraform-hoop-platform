# The agent lifecycle belongs to the workspace that deploys it. agent.create = false
# adopts an agent that already exists, because Hoop issues the key only once.
resource "terracurl_request" "agent" {
  count = var.agent.create ? 1 : 0

  name           = var.agent_name
  url            = "${var.agent.api_url}/agents"
  method         = "POST"
  response_codes = ["201"]

  headers = {
    Authorization = "Bearer ${var.agent.api_key}"
    Content-Type  = "application/json"
  }
  request_body = jsonencode({
    name = var.agent_name
    mode = var.agent.mode
  })

  # The create response carries the DSN with the one-time key, not the agent UUID.
  response_sensitive = true
  skip_read          = true

  # Hoop accepts the agent name for deletion. 404 keeps destroy idempotent when the
  # agent was already removed. Creation stays 201-only: a 409 would mean the agent
  # exists and its one-time key cannot be recovered, so failing there is correct.
  destroy_url            = "${var.agent.api_url}/agents/${urlencode(var.agent_name)}"
  destroy_method         = "DELETE"
  destroy_headers        = { Authorization = "Bearer ${var.agent.api_key}" }
  destroy_response_codes = ["204", "404"]

  lifecycle {
    precondition {
      condition     = var.agent_name != null
      error_message = "agent_name is required when agent.create is true."
    }
  }
}

# The create response has no ID, so resolve the UUID by name. Depending on the
# creation guarantees connections cannot race the agent.
data "http" "agent" {
  count = var.agent.create ? 1 : 0

  url = "${var.agent.api_url}/agents/${urlencode(var.agent_name)}"
  request_headers = {
    Authorization = "Bearer ${var.agent.api_key}"
    Accept        = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Hoop agent lookup failed: HTTP ${self.status_code} ${self.response_body}"
    }
  }

  depends_on = [terracurl_request.agent]
}
