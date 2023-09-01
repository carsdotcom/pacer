defmodule Pacer.Workflow.FieldNotSet do
  @moduledoc """
  Struct set as the initial value for fields in
  a `Pacer.Workflow` definition when no explicit default
  value is provided.
  """

  defstruct []

  defimpl Inspect do
    def inspect(_not_set, _opts) do
      ~s(#Pacer.Workflow.FieldNotSet<>)
    end
  end
end
