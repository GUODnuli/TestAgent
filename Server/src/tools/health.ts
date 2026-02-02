import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { z } from 'zod'

export function registerHealthTools(server: McpServer): void {
  server.tool(
    'health_check',
    'Check if the MCP server is running and responsive',
    {},
    async () => ({
      content: [
        {
          type: 'text' as const,
          text: JSON.stringify({
            status: 'healthy',
            server: 'testagent-mcp-server',
            version: '1.0.0',
            timestamp: new Date().toISOString(),
          }),
        },
      ],
    })
  )

  server.tool(
    'get_server_info',
    'Get information about the MCP server and available tool groups',
    {
      verbose: z.boolean().optional().describe('Include detailed capability information'),
    },
    async ({ verbose }) => {
      const info: Record<string, unknown> = {
        name: 'testagent-mcp-server',
        version: '1.0.0',
        description: 'TestAgent MCP Server - 浏览器自动化与自定义工具',
        toolGroups: ['health', 'playwright (via @playwright/mcp)'],
      }

      if (verbose) {
        info.capabilities = {
          tools: true,
          resources: false,
          prompts: false,
        }
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: JSON.stringify(info, null, 2),
          },
        ],
      }
    }
  )
}
