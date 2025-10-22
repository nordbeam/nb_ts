import Config

config :nb_ts,
  # Larger pool in production
  tsgo_pool_size: max(System.schedulers_online() * 2, 20),

  # Longer timeout for complex types
  tsgo_timeout: 60_000
