import Config

# Quiet by default for menard's own runs and tests. The MCP door does not rely on this: a host
# that takes menard as a dep never loads it, so `mix menard.mcp` sets up its own logger.
config :logger, level: :warning
