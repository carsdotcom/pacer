defmodule Pacer.Workflow.FieldNotSetTest do
  use ExUnit.Case, async: true

  describe "Inspect protocol implementation" do
    test "inspect" do
      assert "#Pacer.Workflow.FieldNotSet<>" == inspect(%Pacer.Workflow.FieldNotSet{}, [])
    end
  end
end
