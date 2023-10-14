defmodule Pacer.Config do
  @moduledoc """
  The #{inspect(__MODULE__)} provides functions for
  extracting user-provided configuration values specific
  to Pacer.
  """

  @spec batch_telemetry_options(module()) :: map()
  def batch_telemetry_options(workflow_module) do
    case :persistent_term.get({__MODULE__, workflow_module, :batch_telemetry_options}, :unset) do
      :unset -> fetch_and_write({workflow_module, :batch_telemetry_options})
      config -> config
    end
  end

  @spec fetch_and_write({workflow_module, key}) :: map() when key: atom(), workflow_module: module()
  defp fetch_and_write({workflow_module, key}) do
    global_config = Application.get_env(:pacer, key) || %{}
    module_config = workflow_module.__config__(key) || %{}

    global_config
    |> Map.merge(module_config)
    |> tap(&:persistent_term.put({__MODULE__, workflow_module, key}, &1))
  end
end
