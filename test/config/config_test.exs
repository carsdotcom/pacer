defmodule Pacer.ConfigTest do
  use ExUnit.Case

  alias Pacer.Config

  describe "batch_telemetry_options/1" do
    defmodule NoOptions do
      use Pacer.Workflow

      graph do
        field(:foo)
      end
    end

    test "returns an empty map if no user-provided options are available" do
      assert Config.batch_telemetry_options(NoOptions) == %{}
    end
  end
end
