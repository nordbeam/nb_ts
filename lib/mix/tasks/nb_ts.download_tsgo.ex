defmodule Mix.Tasks.NbTs.DownloadTsgo do
  @moduledoc """
  Downloads tsgo binaries for all supported platforms.

  ## Usage

      mix nb_ts.download_tsgo

  ## Environment Variables

    * `TSGO_VERSION` - Version to download (default: 2025-10-22)
    * `TSGO_PLATFORMS` - Comma-separated platforms (default: all)

  ## Examples

      # Download all platforms
      mix nb_ts.download_tsgo

      # Download specific version
      TSGO_VERSION=2025-10-15 mix nb_ts.download_tsgo

      # Download only current platform
      TSGO_PLATFORMS=darwin-arm64 mix nb_ts.download_tsgo
  """

  use Mix.Task

  @shortdoc "Downloads tsgo binaries"

  @version System.get_env("TSGO_VERSION") || "2025-10-22"
  @base_url "https://github.com/sxzz/tsgo-releases/releases/download/#{@version}"

  @platforms %{
    "darwin-amd64" => "tar.gz",
    "darwin-arm64" => "tar.gz",
    "linux-amd64" => "tar.gz",
    "linux-arm64" => "tar.gz",
    "windows-amd64" => "zip",
    "windows-arm64" => "zip"
  }

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    # Ensure :inets and :ssl applications are started for httpc
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    priv_dir = Path.join([Mix.Project.app_path(), "priv", "tsgo"])
    File.mkdir_p!(priv_dir)

    platforms = get_platforms()

    Mix.shell().info("Downloading tsgo binaries (version #{@version})...")

    for platform <- platforms do
      download_platform(platform, priv_dir)
    end

    Mix.shell().info("")
    Mix.shell().info("✓ All tsgo binaries downloaded to #{priv_dir}")
    list_binaries(priv_dir)
  end

  defp get_platforms do
    case System.get_env("TSGO_PLATFORMS") do
      nil -> Map.keys(@platforms)
      str -> String.split(str, ",", trim: true)
    end
  end

  defp download_platform(platform, priv_dir) do
    ext = Map.fetch!(@platforms, platform)
    filename = "tsgo-#{platform}.#{ext}"
    url = "#{@base_url}/#{filename}"

    Mix.shell().info("  Downloading #{filename}...")

    case download_file(url) do
      {:ok, data} ->
        case extract_binary(platform, ext, data, priv_dir) do
          :ok ->
            Mix.shell().info("    ✓ Installed tsgo-#{platform}")

          {:error, reason} ->
            Mix.shell().error("    ✗ Extraction failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("    ✗ Download failed: #{inspect(reason)}")
    end
  end

  defp download_file(url) do
    url_charlist = String.to_charlist(url)

    case :httpc.request(:get, {url_charlist, []}, [{:timeout, 60_000}], [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_binary(platform, "tar.gz", data, priv_dir) do
    # Write to temp file
    temp_file = Path.join(System.tmp_dir!(), "tsgo-#{platform}.tar.gz")
    File.write!(temp_file, data)

    # Extract
    :erl_tar.extract(temp_file, [:compressed, {:cwd, String.to_charlist(priv_dir)}])

    # Rename
    File.rename!(
      Path.join(priv_dir, "tsgo"),
      Path.join(priv_dir, "tsgo-#{platform}")
    )

    # Set executable
    File.chmod!(Path.join(priv_dir, "tsgo-#{platform}"), 0o755)

    File.rm!(temp_file)
    :ok
  end

  defp extract_binary(platform, "zip", data, priv_dir) do
    try do
      # Write to temp file
      temp_file = Path.join(System.tmp_dir!(), "tsgo-#{platform}.zip")
      File.write!(temp_file, data)

      # Extract to temp directory first
      temp_extract_dir = Path.join(System.tmp_dir!(), "tsgo-extract-#{platform}")
      File.mkdir_p!(temp_extract_dir)

      case :zip.extract(temp_file, [{:cwd, String.to_charlist(temp_extract_dir)}]) do
        {:ok, files} ->
          # Find the tsgo.exe file in the extracted files
          exe_file =
            Enum.find(files, fn file ->
              file_str = to_string(file)
              String.ends_with?(file_str, "tsgo.exe")
            end)

          if exe_file do
            source_file = Path.join(temp_extract_dir, to_string(exe_file))
            dest_file = Path.join(priv_dir, "tsgo-#{platform}.exe")

            File.rename!(source_file, dest_file)
            # Set executable (no-op on Windows)
            File.chmod!(dest_file, 0o755)

            # Cleanup
            File.rm!(temp_file)
            File.rm_rf!(temp_extract_dir)
            :ok
          else
            {:error, "tsgo.exe not found in extracted archive"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp list_binaries(priv_dir) do
    Mix.shell().info("")
    Mix.shell().info("Installed binaries:")

    priv_dir
    |> File.ls!()
    |> Enum.each(fn file ->
      path = Path.join(priv_dir, file)
      size = File.stat!(path).size
      size_mb = Float.round(size / 1_024 / 1_024, 1)
      Mix.shell().info("  #{file} (#{size_mb} MB)")
    end)
  end
end
