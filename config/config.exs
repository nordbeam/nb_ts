import Config

config :nb_ts,
  # Pool size for tsgo validators
  # Recommended: max(System.schedulers_online(), 10)
  tsgo_pool_size: max(System.schedulers_online(), 10),

  # Validation timeout (milliseconds)
  tsgo_timeout: 30_000,

  # Fallback to oxc if tsgo unavailable
  fallback_to_oxc: true

# Environment-specific overrides
import_config "#{config_env()}.exs"
