defmodule Pacer.Config do
  @moduledoc """
  The #{inspect(__MODULE__)} module provides functions for
  extracting user-provided configuration values specific
  to Pacer.
  """

  @doc """
  Fetches configuration options for extending the metadata provided in the
  `[:pacer, :execute_vertex, :start | :stop | :exception]` events for batched resolvers.

  The configuration must be set under the key `:batch_telemetry_options` at the application
  level (i.e., `Application.get_env(:pacer, :batch_telemetry_options)`) or when defining the
  workflow itself (`use Pacer.Workflow, batch_telemetry_options: <opts>`).

  The batch_telemetry_options defined by the user must be either:
    - a keyword list, or
    - a {module, function, args} mfa tuple; when invoked, this function must return a keyword list

  The keyword list of values returned by the mfa-style config, or the hardcoded keyword list, is
  fetched and converted into a map that gets merged into the telemetry event metadata for batched resolvers.
  """
  @spec batch_telemetry_options(module()) :: keyword() | {module(), atom(), list()}
  def batch_telemetry_options(workflow_module) do
    case :persistent_term.get({__MODULE__, workflow_module, :batch_telemetry_options}, :unset) do
      :unset -> fetch_and_write({workflow_module, :batch_telemetry_options})
      config -> config
    end
  end

  @doc """
  Takes the batch_telemetry_options configuration, invoking mfa-style config if available,
  and converts the batch_telemetry_options keyword list into a map that gets merged into
  the metadata for the `[:pacer, :execute_vertex, :start | :stop | :exception]` events for
  batched resolvers.
  """
  @spec fetch_batch_telemetry_options(module()) :: map()
  def fetch_batch_telemetry_options(workflow_module) do
    case batch_telemetry_options(workflow_module) do
      {mod, fun, args} -> Map.new(apply(mod, fun, args))
      opts -> Map.new(opts)
    end
  end

  @spec fetch_and_write({workflow_module, :batch_telemetry_options}) ::
          keyword() | {module(), atom(), list()}
        when workflow_module: module()
  defp fetch_and_write({workflow_module, :batch_telemetry_options = key}) do
    global_config = Application.get_env(:pacer, key) || []
    module_config = workflow_module.__config__(key) || []

    cond do
      is_list(global_config) && is_list(module_config) ->
        global_config
        |> Keyword.merge(module_config)
        |> tap(&:persistent_term.put({__MODULE__, workflow_module, key}, &1))

      match?({_m, _f, _a}, module_config) || is_list(module_config) ->
        tap(module_config, &:persistent_term.put({__MODULE__, workflow_module, key}, &1))

      match?({_m, _f, _a}, global_config) || is_list(global_config) ->
        tap(global_config, &:persistent_term.put({__MODULE__, workflow_module, key}, &1))

      true ->
        tap([], &:persistent_term.put({__MODULE__, workflow_module, key}, &1))
    end
  end
end
