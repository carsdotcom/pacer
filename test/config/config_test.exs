defmodule Pacer.ConfigTest do
  use ExUnit.Case, async: false

  alias Pacer.ConfigTest.NoOptions
  alias Pacer.Config

  describe "batch_telemetry_options/1" do
    setup do
      default = Application.get_env(:pacer, :batch_telemetry_options)

      on_exit(fn ->
        :persistent_term.erase({Config, NoOptions, :batch_telemetry_options})
        :persistent_term.erase({Config, TestBatchConfig, :batch_telemetry_options})
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
      assert Config.batch_telemetry_options(NoOptions) == []
    end

    test "returns global batch_telemetry_options if no module-level options are provided" do
      Application.put_env(:pacer, :batch_telemetry_options, foo: "bar")
      assert Config.batch_telemetry_options(NoOptions) == [foo: "bar"]
    end

    test "accepts {module, function, args} tuples for batch_telemetry_options from global config" do
      Application.put_env(:pacer, :batch_telemetry_options, {MyTelemetryOptions, :run, []})
      assert Config.batch_telemetry_options(NoOptions) == {MyTelemetryOptions, :run, []}
    end

    defmodule TestBatchConfig do
      use Pacer.Workflow, batch_telemetry_options: [batched: "config"]

      graph do
        field(:foo)
      end
    end

    test "returns module-level options when provided" do
      assert Config.batch_telemetry_options(TestBatchConfig) == [batched: "config"]
    end

    test "module-level batch_telemetry_options overrides global batch_telemetry_options" do
      Application.put_env(:pacer, :batch_telemetry_options,
        batched: "this value should be overridden"
      )

      assert Config.batch_telemetry_options(TestBatchConfig) == [batched: "config"]
    end

    defmodule TestConfigWithMFA do
      use Pacer.Workflow, batch_telemetry_options: {__MODULE__, :batch_telemetry_opts, []}

      graph do
        field(:foo)
      end
    end

    test "returns {module, function, args} options stored in module config" do
      assert Config.batch_telemetry_options(TestConfigWithMFA) ==
               {TestConfigWithMFA, :batch_telemetry_opts, []}
    end

    test "module config overrides global config when both are present and use {module, function, args} style config" do
      Application.put_env(:pacer, :batch_telemetry_options, {PacerGlobal, :default_options, []})

      assert Config.batch_telemetry_options(TestConfigWithMFA) ==
               {TestConfigWithMFA, :batch_telemetry_opts, []}
    end
  end

  describe "fetch_batch_telemetry_options/1" do
    defmodule MyWorkflowExample do
      use Pacer.Workflow

      graph do
        field(:foo)
      end

      def default_options do
        [
          foo: "bar",
          baz: "quux"
        ]
      end
    end

    test "invokes {module, fun, args} style config when present and converts the keyword list returned into a map" do
      Application.put_env(
        :pacer,
        :batch_telemetry_options,
        {MyWorkflowExample, :default_options, []}
      )

      assert Config.fetch_batch_telemetry_options(MyWorkflowExample) == %{foo: "bar", baz: "quux"}
    end

    test "converts keyword list style configuration into a map" do
      Application.put_env(:pacer, :batch_telemetry_options, foo: "bar", baz: "quux")

      assert Config.fetch_batch_telemetry_options(MyWorkflowExample) == %{foo: "bar", baz: "quux"}
    end
  end
end
