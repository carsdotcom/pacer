defmodule Pacer.Config do
  @moduledoc """
  The #{inspect(__MODULE__)} module provides functions for
  extracting user-provided configuration values specific
  to Pacer.
  """

  @spec batch_telemetry_options(module()) :: keyword() | {module(), atom(), list()}
  def batch_telemetry_options(workflow_module) do
    case :persistent_term.get({__MODULE__, workflow_module, :batch_telemetry_options}, :unset) do
      :unset -> fetch_and_write({workflow_module, :batch_telemetry_options})
      config -> config
    end
  end

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
