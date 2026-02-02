import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { registerHealthTools } from './health.js'

export function registerTools(server: McpServer): void {
  registerHealthTools(server)
}
