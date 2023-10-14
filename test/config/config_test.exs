defmodule Pacer.ConfigTest do
  use ExUnit.Case

  alias Pacer.Config

  describe "batch_telemetry_options/1" do
    setup do
      default = Application.get_env(:pacer, :batch_telemetry_options)

      on_exit(fn ->
        Application.put_env(:pacer, :batch_telemetry_options, default)
      end)

      :ok
    end

    defmodule NoOptions do
      use Pacer.Workflow

      graph do
        field(:foo)
      end
    end

    test "returns an empty map if no user-provided options are available" do
      assert Config.batch_telemetry_options(NoOptions) == %{}
    end

    test "returns global batch_telemetry_options if no module-level options are provided" do
      Application.put_env(:pacer, :batch_telemetry_options, %{foo: "bar"})
      assert Config.batch_telemetry_options(NoOptions) == %{foo: "bar"}
    end

    defmodule TestBatchConfig do
      use Pacer.Workflow, batch_telemetry_options: %{batched: "config"}

      graph do
        field(:foo)
      end
    end

    test "returns module-level options when provided" do
      assert Config.batch_telemetry_options(TestBatchConfig) == %{batched: "config"}
    end
  end
end
