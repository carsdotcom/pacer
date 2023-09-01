defmodule Pacer.Workflow.Visualization do
  @moduledoc """
  A small wrapper around a Pacer Workflow's `visualization` metadata function.

  This stringed strict diagraph that is returned can be used in graphviz or some other graph visualization tool.
  """

  @spec visualize(module(), Keyword.t()) :: :ok
  def visualize(workflow, options \\ []) do
    path = Keyword.get(options, :path, File.cwd!() <> "/")

    filename =
      Keyword.get(
        options,
        :filename,
        "#{inspect(workflow)}" <>
          "_strict_digraph_string_" <> "#{Calendar.strftime(NaiveDateTime.utc_now(), "%Y-%m-%d")}"
      )

    {:ok, strict_digraph_string} = workflow.__graph__(:visualization)
    File.write!(path <> "#{filename}", strict_digraph_string)
  end
end
