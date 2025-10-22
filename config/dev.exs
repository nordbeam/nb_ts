import Config

config :nb_ts,
  # Smaller pool in dev
  tsgo_pool_size: 5,

  # Shorter timeout in dev
  tsgo_timeout: 10_000
