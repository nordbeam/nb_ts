ExUnit.start()

# Start the application to ensure TsgoPool is running
{:ok, _} = Application.ensure_all_started(:nb_ts)
