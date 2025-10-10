defmodule NbTs.Validator do
  @moduledoc false

  # Use Rustler directly to load from the local priv directory
  use Rustler,
    otp_app: :nb_ts,
    crate: "typescript_validator",
    load_from: {:nb_ts, "priv/native/typescript_validator"}

  # NIF function stub - replaced at load time
  def validate(_typescript), do: :erlang.nif_error(:nif_not_loaded)
end
