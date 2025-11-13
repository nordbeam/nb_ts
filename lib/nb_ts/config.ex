defmodule NbTs.Config do
  @moduledoc """
  Configuration module for NbTs.
  Provides configuration values from application environment.
  """

  @doc """
  Returns whether auto-generation is enabled.
  Defaults to true in dev environment.
  """
  def auto_generate? do
    Application.get_env(:nb_ts, :auto_generate, Mix.env() == :dev)
  end

  @doc """
  Returns whether file watching is enabled.
  Defaults to true in dev environment.
  """
  def watch? do
    Application.get_env(:nb_ts, :watch, Mix.env() == :dev)
  end

  @doc """
  Returns the directories to watch for changes.
  """
  def watch_dirs do
    Application.get_env(:nb_ts, :watch_dirs, ["lib"])
  end

  @doc """
  Returns the pool size for tsgo processes.
  """
  def pool_size do
    Application.get_env(:nb_ts, :pool_size, System.schedulers_online())
  end

  @doc """
  Returns the output directory for generated TypeScript files.
  """
  def output_dir do
    Application.get_env(:nb_ts, :output_dir, "assets/js/types")
  end

  @doc """
  Returns whether to validate generated TypeScript.
  """
  def validate? do
    Application.get_env(:nb_ts, :validate, false)
  end

  @doc """
  Returns whether to show verbose output.
  """
  def verbose? do
    Application.get_env(:nb_ts, :verbose, false)
  end
end
