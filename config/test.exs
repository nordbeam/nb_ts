import Config

config :nb_ts,
  # Single worker for tests
  tsgo_pool_size: 1,

  # Fast timeout for tests
  tsgo_timeout: 5_000
