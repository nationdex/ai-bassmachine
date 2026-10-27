-- AI Bass Machine - Type Definition Module (Teal)

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

global record AgentSkill
  name: string
  dir_name: string
  description: string
  path: string
  raw: string
  body: string
  installed_in: {string}
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
  new: function(config: any): EnvManagerModule
  get_targets: function(self: EnvManagerModule): {AgentTargetInfo}
  list_all: function(self: EnvManagerModule): {AgentTargetInfo}
  add_mcp: function(self: EnvManagerModule, server_name: string, spec: any, target: string): {any}
  remove_mcp: function(self: EnvManagerModule, server_name: string, target: string): {any}
  configure_mcp: function(self: EnvManagerModule, server_name: string, updates: any, target: string): {any}
  get_target_mcp_spec: function(self: EnvManagerModule, target_id: string, server_name: string): any
end

global record SkillManagerModule
  new: function(config: any): SkillManagerModule
  get_targets: function(self: SkillManagerModule): {any}
  list_all: function(self: SkillManagerModule): {AgentSkill}
  install_skill: function(self: SkillManagerModule, name: string, content: string, target: string): {any}
  remove_skill: function(self: SkillManagerModule, name: string, target: string): {any}
  sync_skill_to_all: function(self: SkillManagerModule, name: string): boolean, any
  refresh_marketplace: function(self: SkillManagerModule): boolean, integer
  get_marketplace_skills: function(self: SkillManagerModule, query: string): {any}
  install_from_marketplace: function(self: SkillManagerModule, skill_item: any, target_id: string): boolean, {any}, string
end

global record BassMachineModule
  version: string
  create_config: function(path: string): BassMachineConfig
  run_mcp: function(cmd: string): boolean, {McpTool}
end
