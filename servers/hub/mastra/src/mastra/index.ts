import { Mastra } from '@mastra/core'
import { LibSQLStore } from '@mastra/libsql'
import { chatRoute } from '@mastra/ai-sdk'
import { hubAgent, hubAgent27b, hubAgent35b } from './agents/hub-agent'

const port = Number(process.env.PORT ?? 4111)
const dbUrl = process.env.MASTRA_DB_URL ?? 'file:/data/mastra.db'

export const mastra = new Mastra({
  agents: {
    hubAgent,
    hubAgent27b,
    hubAgent35b,
  },
  storage: new LibSQLStore({
    id: 'hub-mastra-storage',
    url: dbUrl,
  }),
  server: {
    host: '0.0.0.0',
    port,
    apiRoutes: [
      chatRoute({
        path: '/chat/:agentId',
      }),
    ],
    build: {
      openAPIDocs: true,
      swaggerUI: true,
    },
  },
})
