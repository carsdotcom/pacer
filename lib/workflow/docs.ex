defmodule Pacer.Docs do
  @moduledoc """
  This module is responsible for extracting information provided to fields
  in a Pacer.Workflow `graph` definition and turning that information into
  docs that can be rendered into a module's documentation.
  """
  alias Pacer.Workflow.FieldNotSet

  defmacro generate do
    quote do
      docs =
        Enum.reduce(@pacer_docs, "\n## Pacer Fields:\n\n", fn
          {field, doc}, markdown ->
            markdown <>
              "\n - `#{field}`\n#{Pacer.Docs.write_doc(doc)}#{Pacer.Docs.write_default(Keyword.get(@pacer_struct_fields, field))}#{Pacer.Docs.write_dependencies(Keyword.get(@pacer_dependencies, field))}"

          {field, batch, doc}, markdown ->
            field_dependencies = @pacer_batch_dependencies |> List.keyfind!(field, 1) |> elem(2)

            markdown <>
              "\n - `#{field}`\n#{Pacer.Docs.write_doc(doc)}\t - **Batch**: `#{batch}`\n#{Pacer.Docs.write_default(Keyword.get(@pacer_struct_fields, field))}#{Pacer.Docs.write_dependencies(field_dependencies)}"
        end)

      case Module.get_attribute(__MODULE__, :moduledoc) do
        {v, original_doc} ->
          Module.put_attribute(
            __MODULE__,
            :moduledoc,
            {v, original_doc <> docs}
          )

        nil ->
          Module.put_attribute(__MODULE__, :moduledoc, {__ENV__.line, docs})
      end
    end
  end

  def write_doc(""), do: ""
  def write_doc(doc), do: "\t - #{doc}\n"

  def write_default(%FieldNotSet{}), do: ""
  def write_default(default), do: "\t - **Default**: `#{inspect(default)}`\n"

  def write_dependencies([]), do: "\t - *No dependencies*\n"
  def write_dependencies(deps), do: "\t - **Depends on**: `#{inspect(deps)}`\n"
end
