-- MCP Bass Machine - Type Definition Module (Teal)

global record McpToolInputSchema
  type: string
  properties: {string:any}
  required: {string}
end

global record McpTool
  name: string
  description: string
  inputSchema: McpToolInputSchema
end

global record McpServerSpec
  id: string
  name: string
  author: string
  source: string
  description: string
  command: string
  args: {string}
  tags: {string}
  category: string
end

global record HistoryRecord
  id: string
  name: string
  command: string
  status: string
  tools_count: integer
  duration_ms: integer
  timestamp: integer
  time_formatted: string
end

global record ProviderConfig
  name: string
  base_url: string
  api_key: string
  default_model: string
end

global record GeneralConfig
  app_name: string
  log_level: string
  history_file: string
  auto_clean_history: boolean
  max_history_entries: integer
  history_retention_hours: integer
end

global record UiConfig
  theme: string
  frame_rate: integer
  show_fps: boolean
  mouse_support: boolean
  bass_meter: boolean
end

global record AiConfig
  default_provider: string
  default_model: string
  temperature: number
  max_tokens: integer
  request_timeout_seconds: integer
end

global record BassMachineConfig
  general: GeneralConfig
  ui: UiConfig
  ai: AiConfig
  providers: {string:ProviderConfig}
end

global record AiCompletionResult
  content: string
  reasoning: string
  model: string
  tool_calls: {any}
end

global record AgentTargetInfo
  id: string
  name: string
  path: string
  exists: boolean
  servers: {string:any}
end

global record EnvManagerModule
  new: function(): EnvManagerModule
  get_targets: function(self: EnvManagerModule): {AgentTargetInfo}
  list_all: function(self: EnvManagerModule): {AgentTargetInfo}
  add_mcp: function(self: EnvManagerModule, server_name: string, spec: any, target: string): {any}
  remove_mcp: function(self: EnvManagerModule, server_name: string, target: string): {any}
end

global record BassMachineModule
  version: string
  create_config: function(path: string): BassMachineConfig
  run_mcp: function(cmd: string): boolean, {McpTool}
end
