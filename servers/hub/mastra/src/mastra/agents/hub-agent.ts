import { Agent } from '@mastra/core/agent'
import { createOpenAICompatible } from '@ai-sdk/openai-compatible'

const defaultModel = process.env.MASTRA_MODEL ?? 'qwen3.5-9b'
const openaiBaseUrl = process.env.OPENAI_BASE_URL ?? 'http://192.168.20.41:8000/v1'
const openaiApiKey = process.env.OPENAI_API_KEY ?? 'local-llama'

const llamaProvider = createOpenAICompatible({
  name: 'llama',
  baseURL: openaiBaseUrl,
  apiKey: openaiApiKey,
  transformRequestBody: (body) => {
    if (typeof body.model === 'string') {
      return {
        ...body,
        model: body.model.replace(/^openai\//, ''),
      }
    }
    return body
  },
})

const instructions = `
You are the assistant for the crussell hub machine and homelab services.
Keep responses concise, actionable, and operator-focused.
When giving shell commands, prefer safe defaults and call out risk clearly.
`

function createHubAgent(id: string, name: string, modelId: string) {
  return new Agent({
    id,
    name,
    instructions,
    model: llamaProvider.chatModel(modelId),
  })
}

export const hubAgent = createHubAgent('hub-agent', 'Hub Agent', defaultModel)
export const hubAgent27b = createHubAgent('hub-agent-27b', 'Hub Agent 27B', 'qwen3.5-27b')
export const hubAgent35b = createHubAgent('hub-agent-35b', 'Hub Agent 35B A3B', 'qwen3.5-35b-a3b')
